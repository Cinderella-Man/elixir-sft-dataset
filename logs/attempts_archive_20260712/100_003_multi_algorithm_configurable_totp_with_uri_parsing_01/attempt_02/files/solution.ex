defmodule FlexTOTP do
  @moduledoc """
  A configurable RFC 6238 Time-Based One-Time Password (TOTP) implementation.

  Unlike a classic hard-wired SHA1 / 6-digit / 30-second generator, `FlexTOTP`
  takes the HMAC algorithm, code length, and step period as options. It supports
  the `:sha1`, `:sha256`, and `:sha512` algorithms and can build `otpauth://`
  provisioning URIs as well as parse them back into a configuration map.

  Everything is built on the OTP standard library only — `:crypto` for HMAC and
  random bytes, and `URI` for provisioning-URI handling. Base32 encoding and
  decoding (RFC 4648, uppercase, unpadded) are implemented here directly.
  """

  import Bitwise

  @base32_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @type algorithm :: :sha1 | :sha256 | :sha512

  @doc """
  Generates a cryptographically random, base32-encoded secret.

  `bytes` is the number of bytes of entropy to draw from
  `:crypto.strong_rand_bytes/1` (default `20`). The returned string uses the
  RFC 4648 uppercase alphabet with no padding characters.
  """
  @spec generate_secret(non_neg_integer()) :: String.t()
  def generate_secret(bytes \\ 20) do
    bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Generates a zero-padded numeric TOTP code for `secret`.

  Options:

    * `:time` — UNIX seconds (default `:os.system_time(:second)`)
    * `:algorithm` — `:sha1` | `:sha256` | `:sha512` (default `:sha1`)
    * `:digits` — code length (default `6`)
    * `:period` — step size in seconds (default `30`)

  The step is `div(time, period)`, HMACed (as a big-endian 8-byte integer) with
  the base32-decoded secret, dynamically truncated per RFC 4226, reduced modulo
  `10^digits`, and left-padded with zeros to exactly `digits` characters.
  """
  @spec generate_code(String.t(), keyword()) :: String.t()
  def generate_code(secret, opts \\ []) do
    time = Keyword.get(opts, :time, :os.system_time(:second))
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)

    secret
    |> code_integer(time, algorithm, digits, period)
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  @doc """
  Validates `code` against `secret` for the current (or given) time.

  `code` may be a string or an integer. Accepts the same `:time`,
  `:algorithm`, `:digits`, and `:period` options as `generate_code/2`, plus:

    * `:window` — number of steps to check in each direction (default `1`)

  Returns `true` when the code matches any step within `±window`, else `false`.
  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ []) do
    time = Keyword.get(opts, :time, :os.system_time(:second))
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)
    window = Keyword.get(opts, :window, 1)

    target = normalize_code(code)

    Enum.any?(-window..window, fn offset ->
      shifted = time + offset * period
      code_integer(secret, shifted, algorithm, digits, period) == target
    end)
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI.

  The label is `issuer:account_name` with both parts URI-encoded. Query
  parameters `secret`, `issuer`, `algorithm`, `digits`, and `period` are
  included. `:algorithm` is emitted uppercase (`SHA1`, `SHA256`, `SHA512`,
  default `SHA1`); `:digits` defaults to `6` and `:period` to `30`.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), keyword()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)

    label =
      encode_component(issuer) <> ":" <> encode_component(account_name)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", algorithm_name(algorithm)},
        {"digits", Integer.to_string(digits)},
        {"period", Integer.to_string(period)}
      ])

    "otpauth://totp/" <> label <> "?" <> query
  end

  @doc """
  Parses an `otpauth://` provisioning URI into a configuration map.

  On success returns `{:ok, map}` with keys `:type`, `:issuer`,
  `:account_name`, `:secret`, `:algorithm`, `:digits`, and `:period`. The
  `:issuer` falls back to the issuer portion of the label when the `issuer`
  query parameter is absent. Any string that is not an `otpauth://` URI
  returns `:error`.
  """
  @spec parse_uri(String.t()) :: {:ok, map()} | :error
  def parse_uri(uri) when is_binary(uri) do
    parsed = URI.parse(uri)

    case parsed.scheme do
      "otpauth" -> {:ok, build_config(parsed)}
      _ -> :error
    end
  end

  # --- Internal helpers -----------------------------------------------------

  @spec build_config(URI.t()) :: map()
  defp build_config(%URI{} = parsed) do
    params = URI.decode_query(parsed.query || "")
    label = URI.decode(String.trim_leading(parsed.path || "", "/"))

    {label_issuer, account_name} =
      case String.split(label, ":", parts: 2) do
        [issuer_part, account_part] -> {issuer_part, account_part}
        [account_part] -> {nil, account_part}
      end

    algorithm = parse_algorithm(Map.get(params, "algorithm"))

    %{
      type: parsed.host,
      issuer: Map.get(params, "issuer", label_issuer),
      account_name: account_name,
      secret: Map.get(params, "secret"),
      algorithm: algorithm,
      digits: parse_integer(Map.get(params, "digits"), 6),
      period: parse_integer(Map.get(params, "period"), 30)
    }
  end

  @spec code_integer(String.t(), integer(), algorithm(), pos_integer(), pos_integer()) ::
          non_neg_integer()
  defp code_integer(secret, time, algorithm, digits, period) do
    step = div(time, period)
    message = <<step::big-unsigned-integer-size(64)>>
    key = base32_decode(secret)
    hmac = :crypto.mac(:hmac, hash_algorithm(algorithm), key, message)
    truncate(hmac, digits)
  end

  @spec truncate(binary(), pos_integer()) :: non_neg_integer()
  defp truncate(hmac, digits) do
    offset = :binary.at(hmac, byte_size(hmac) - 1) &&& 0x0F
    <<_top::1, code::31>> = binary_part(hmac, offset, 4)
    rem(code, Integer.pow(10, digits))
  end

  @spec normalize_code(String.t() | integer()) :: integer()
  defp normalize_code(code) when is_integer(code), do: code
  defp normalize_code(code) when is_binary(code), do: String.to_integer(code)

  @spec hash_algorithm(algorithm()) :: :sha | :sha256 | :sha512
  defp hash_algorithm(:sha1), do: :sha
  defp hash_algorithm(:sha256), do: :sha256
  defp hash_algorithm(:sha512), do: :sha512

  @spec algorithm_name(algorithm()) :: String.t()
  defp algorithm_name(:sha1), do: "SHA1"
  defp algorithm_name(:sha256), do: "SHA256"
  defp algorithm_name(:sha512), do: "SHA512"

  @spec parse_algorithm(String.t() | nil) :: algorithm()
  defp parse_algorithm(nil), do: :sha1

  defp parse_algorithm(value) when is_binary(value) do
    case String.upcase(value) do
      "SHA256" -> :sha256
      "SHA512" -> :sha512
      _ -> :sha1
    end
  end

  @spec parse_integer(String.t() | nil, integer()) :: integer()
  defp parse_integer(nil, default), do: default
  defp parse_integer(value, _default) when is_binary(value), do: String.to_integer(value)

  @spec encode_component(String.t()) :: String.t()
  defp encode_component(value) do
    URI.encode(value, &unreserved?/1)
  end

  @spec unreserved?(char()) :: boolean()
  defp unreserved?(char) do
    char in ?A..?Z or char in ?a..?z or char in ?0..?9 or char in ~c"-._~"
  end

  # --- Base32 (RFC 4648, uppercase, unpadded) -------------------------------

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) do
    pad = rem(5 - rem(bit_size(binary), 5), 5)
    padded = <<binary::bitstring, 0::size(pad)>>

    for <<value::5 <- padded>>, into: "" do
      <<:binary.at(@base32_alphabet, value)>>
    end
  end

  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(string) do
    bits =
      for <<char <- String.upcase(string)>>, char != ?=, into: <<>> do
        <<base32_index(char)::5>>
      end

    byte_count = div(bit_size(bits), 8)
    <<bytes::binary-size(byte_count), _rest::bitstring>> = bits
    bytes
  end

  @spec base32_index(char()) :: non_neg_integer()
  defp base32_index(char) when char in ?A..?Z, do: char - ?A
  defp base32_index(char) when char in ?2..?7, do: char - ?2 + 26
end
