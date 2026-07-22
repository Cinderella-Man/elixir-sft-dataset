defmodule MultiTOTP do
  @moduledoc """
  A fully configurable implementation of RFC 6238 Time-Based One-Time
  Passwords (TOTP) built on top of RFC 4226 HOTP.

  Unlike a fixed TOTP implementation, `MultiTOTP` lets the caller choose the
  HMAC algorithm (`:sha1`, `:sha256`, `:sha512`), the number of output digits,
  and the length of a time step ("period"). It also supports building and
  parsing `otpauth://` provisioning URIs.

  The module depends only on the Erlang/OTP standard library (`:crypto`,
  `URI`); it has no external dependencies. Base32 encoding/decoding follows
  RFC 4648 (uppercase alphabet `A`–`Z` and `2`–`7`, no padding).
  """

  import Bitwise

  @b32_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @doc """
  Generates a cryptographically random, base32-encoded secret.

  `byte_length` bytes of entropy are drawn from `:crypto.strong_rand_bytes/1`
  and encoded as an unpadded RFC 4648 base32 string. The resulting length is
  `ceil(byte_length * 8 / 5)` characters (the default 20 bytes yields 32
  characters).
  """
  @spec generate_secret(pos_integer()) :: String.t()
  def generate_secret(byte_length \\ 20) do
    byte_length
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Generates a zero-padded numeric TOTP code string.

  Options:

    * `:time` — UNIX seconds (default: current time)
    * `:algorithm` — `:sha1` | `:sha256` | `:sha512` (default: `:sha1`)
    * `:digits` — number of output digits (default: `6`)
    * `:period` — length of a time step in seconds (default: `30`)
  """
  @spec generate_code(String.t(), keyword()) :: String.t()
  def generate_code(secret, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)

    step = div(time, period)
    key = base32_decode(secret)
    message = <<step::big-unsigned-integer-size(64)>>
    hmac = :crypto.mac(:hmac, hash_for(algorithm), key, message)

    hmac
    |> dynamic_truncation()
    |> rem(Integer.pow(10, digits))
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  @doc """
  Validates `code` (a string or integer) against the current time.

  Accepts the same `:time`, `:algorithm`, `:digits`, and `:period` options as
  `generate_code/2`, plus `:window` — the number of steps to check in each
  direction (default `1`). Returns `true` if `code` matches the code produced
  at any step within `±window`, otherwise `false`.
  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)
    window = Keyword.get(opts, :window, 1)

    target =
      code
      |> to_string()
      |> String.pad_leading(digits, "0")

    Enum.any?(-window..window, fn offset ->
      step_time = time + offset * period
      step_opts = Keyword.put(opts, :time, step_time)
      generate_code(secret, step_opts) == target
    end)
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI.

  The label is `issuer:account_name` with both parts URI-encoded. The query
  parameters are `secret`, `issuer`, `algorithm` (uppercase name), `digits`,
  and `period`. Recognized options are `:algorithm` (default `:sha1`),
  `:digits` (default `6`), and `:period` (default `30`).
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), keyword()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)

    label = uri_encode(issuer) <> ":" <> uri_encode(account_name)

    query =
      URI.encode_query(
        secret: secret,
        issuer: issuer,
        algorithm: algorithm_name(algorithm),
        digits: digits,
        period: period
      )

    "otpauth://totp/" <> label <> "?" <> query
  end

  @doc """
  Parses an `otpauth://totp/` URI back into its component parameters.

  On success returns `{:ok, map}` with the keys `:secret`, `:issuer`,
  `:account_name`, `:algorithm`, `:digits`, and `:period`. Returns
  `{:error, :unsupported_algorithm}` if the `algorithm` parameter names an
  unsupported hash, and `{:error, :invalid_uri}` if the input is not an
  `otpauth://totp/` URI.
  """
  @spec parse_uri(String.t()) :: {:ok, map()} | {:error, atom()}
  def parse_uri(uri) do
    case URI.parse(uri) do
      %URI{scheme: "otpauth", host: "totp", path: path, query: query}
      when is_binary(path) ->
        params = URI.decode_query(query || "")

        case parse_algorithm(Map.get(params, "algorithm")) do
          {:ok, algorithm} ->
            {label_issuer, account_name} = split_label(path)

            {:ok,
             %{
               secret: Map.get(params, "secret"),
               issuer: Map.get(params, "issuer", label_issuer),
               account_name: account_name,
               algorithm: algorithm,
               digits: params |> Map.get("digits", "6") |> String.to_integer(),
               period: params |> Map.get("period", "30") |> String.to_integer()
             }}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :invalid_uri}
    end
  end

  # ---------------------------------------------------------------------------
  # RFC 4226 dynamic truncation
  # ---------------------------------------------------------------------------

  @spec dynamic_truncation(binary()) :: non_neg_integer()
  defp dynamic_truncation(hmac) do
    offset = :binary.at(hmac, byte_size(hmac) - 1) &&& 0x0F
    <<_::binary-size(offset), value::big-unsigned-integer-size(32), _::binary>> = hmac
    value &&& 0x7FFFFFFF
  end

  # ---------------------------------------------------------------------------
  # Base32 (RFC 4648, unpadded)
  # ---------------------------------------------------------------------------

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(bin) do
    pad =
      case rem(bit_size(bin), 5) do
        0 -> 0
        r -> 5 - r
      end

    padded = <<bin::bitstring, 0::size(pad)>>
    for <<chunk::5 <- padded>>, into: "", do: <<:binary.at(@b32_alphabet, chunk)>>
  end

  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(str) do
    bits = for <<c <- str>>, into: <<>>, do: <<base32_value(c)::5>>
    byte_count = div(bit_size(bits), 8)
    <<bytes::binary-size(byte_count), _::bitstring>> = bits
    bytes
  end

  @spec base32_value(char()) :: non_neg_integer()
  defp base32_value(c) when c in ?A..?Z, do: c - ?A
  defp base32_value(c) when c in ?2..?7, do: c - ?2 + 26

  # ---------------------------------------------------------------------------
  # URI / algorithm helpers
  # ---------------------------------------------------------------------------

  @spec uri_encode(String.t()) :: String.t()
  defp uri_encode(string) do
    URI.encode(string, &URI.char_unreserved?/1)
  end

  @spec split_label(String.t()) :: {String.t() | nil, String.t()}
  defp split_label(path) do
    raw = String.trim_leading(path, "/")

    case String.split(raw, ":", parts: 2) do
      [only] -> {nil, URI.decode(only)}
      [issuer, account] -> {URI.decode(issuer), URI.decode(account)}
    end
  end

  @spec parse_algorithm(String.t() | nil) ::
          {:ok, :sha1 | :sha256 | :sha512} | {:error, :unsupported_algorithm}
  defp parse_algorithm(nil), do: {:ok, :sha1}

  defp parse_algorithm(name) do
    case String.upcase(name) do
      "SHA1" -> {:ok, :sha1}
      "SHA256" -> {:ok, :sha256}
      "SHA512" -> {:ok, :sha512}
      _ -> {:error, :unsupported_algorithm}
    end
  end

  @spec algorithm_name(:sha1 | :sha256 | :sha512) :: String.t()
  defp algorithm_name(:sha1), do: "SHA1"
  defp algorithm_name(:sha256), do: "SHA256"
  defp algorithm_name(:sha512), do: "SHA512"

  @spec hash_for(:sha1 | :sha256 | :sha512) :: :sha | :sha256 | :sha512
  defp hash_for(:sha1), do: :sha
  defp hash_for(:sha256), do: :sha256
  defp hash_for(:sha512), do: :sha512
end
