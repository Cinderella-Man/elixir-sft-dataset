defmodule TOTP do
  @moduledoc """
  A configurable, multi-algorithm RFC 6238 Time-Based One-Time Password (TOTP)
  generator built exclusively on the Erlang/OTP standard library.

  Every parameter — hash algorithm (`:sha1`, `:sha256`, `:sha512`), digit count,
  and time step (period) — is caller-configurable via options. The module can
  generate cryptographically random base32 secrets, emit numeric codes, validate
  codes with clock-drift tolerance, and both build and parse
  `otpauth://totp/` provisioning URIs.

  Base32 encoding/decoding follows RFC 4648 (uppercase alphabet `A–Z`, `2–7`,
  no padding) and is implemented locally rather than through any library.
  HMAC is computed with `:crypto.mac/4` and dynamic truncation follows
  RFC 4226 §5.3.
  """

  import Bitwise

  @alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @decode_map for {ch, idx} <- Enum.with_index(String.graphemes(@alphabet)),
                  into: %{},
                  do: {ch, idx}

  @doc """
  Generates a cryptographically random, base32-encoded secret.

  The `:bytes` option sets the amount of entropy in bytes (default `20`, i.e.
  160 bits, which yields a 32-character secret). Uses
  `:crypto.strong_rand_bytes/1`.
  """
  @spec generate_secret(keyword()) :: String.t()
  def generate_secret(opts \\ []) do
    bytes = Keyword.get(opts, :bytes, 20)

    bytes
    |> :crypto.strong_rand_bytes()
    |> encode_base32()
  end

  @doc """
  Generates a zero-padded numeric TOTP code for `secret`.

  Options:

    * `:time` — UNIX seconds (default: current time)
    * `:algorithm` — `:sha1`, `:sha256`, or `:sha512` (default `:sha1`)
    * `:digits` — number of digits in the code (default `6`)
    * `:period` — step length in seconds (default `30`)
  """
  @spec generate_code(String.t(), keyword()) :: String.t()
  def generate_code(secret, opts \\ []) do
    time = Keyword.get(opts, :time, System.system_time(:second))
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)

    key = decode_base32(secret)
    step = div(time, period)
    message = <<step::unsigned-big-integer-size(64)>>
    hmac = :crypto.mac(:hmac, crypto_hash(algorithm), key, message)

    hmac
    |> truncate(digits)
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  @doc """
  Validates `code` against `secret`, tolerating clock drift.

  `code` may be a string or an integer (integers are zero-padded to `:digits`
  characters). In addition to `:time`, `:algorithm`, `:digits`, and `:period`
  (same defaults as `generate_code/2`), the `:window` option (default `1`) sets
  the number of steps checked in each direction.

  Returns `true` when `code` matches the code computed at any step in
  `-window..window`, and `false` otherwise.
  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ []) do
    digits = Keyword.get(opts, :digits, 6)
    time = Keyword.get(opts, :time, System.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    period = Keyword.get(opts, :period, 30)
    expected = normalize_code(code, digits)

    Enum.any?(-window..window, fn offset ->
      shifted = time + offset * period
      generate_code(secret, Keyword.put(opts, :time, shifted)) == expected
    end)
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI.

  The label is `issuer:account_name` (URI-encoded). The query parameters are
  `secret`, `issuer`, `algorithm` (uppercase name), `digits`, and `period`.
  The `:algorithm`, `:digits`, and `:period` options share the same defaults as
  `generate_code/2`.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), keyword()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, opts \\ []) do
    algorithm = Keyword.get(opts, :algorithm, :sha1)
    digits = Keyword.get(opts, :digits, 6)
    period = Keyword.get(opts, :period, 30)

    label = encode_label(issuer) <> ":" <> encode_label(account_name)

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
  Parses an `otpauth://totp/` provisioning URI.

  Returns `{:ok, config}` with a map holding `:secret`, `:issuer` (string or
  `nil`), `:algorithm`, `:digits`, and `:period`. Missing `algorithm`, `digits`,
  and `period` default to `:sha1`, `6`, and `30` respectively.

  Returns `:error` when the scheme is not `otpauth`, the host is not `totp`, or
  there is no query string.
  """
  @spec parse_uri(String.t()) :: {:ok, map()} | :error
  def parse_uri(uri) do
    parsed = URI.parse(uri)

    with "otpauth" <- parsed.scheme,
         "totp" <- parsed.host,
         query when is_binary(query) <- parsed.query do
      params = URI.decode_query(query)

      config = %{
        secret: Map.get(params, "secret"),
        issuer: Map.get(params, "issuer"),
        algorithm: parse_algorithm(Map.get(params, "algorithm")),
        digits: parse_int(Map.get(params, "digits"), 6),
        period: parse_int(Map.get(params, "period"), 30)
      }

      {:ok, config}
    else
      _ -> :error
    end
  end

  # --- Internal helpers ----------------------------------------------------

  @spec encode_label(String.t()) :: String.t()
  defp encode_label(part), do: URI.encode(part, &URI.char_unreserved?/1)

  @spec normalize_code(String.t() | integer(), pos_integer()) :: String.t()
  defp normalize_code(code, digits) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(digits, "0")
  end

  defp normalize_code(code, _digits) when is_binary(code), do: code

  @spec truncate(binary(), pos_integer()) :: non_neg_integer()
  defp truncate(hmac, digits) do
    offset = :binary.last(hmac) &&& 0x0F
    <<_::binary-size(offset), b0, b1, b2, b3, _::binary>> = hmac

    value =
      (b0 &&& 0x7F) <<< 24 |||
        b1 <<< 16 |||
        b2 <<< 8 |||
        b3

    rem(value, Integer.pow(10, digits))
  end

  @spec crypto_hash(:sha1 | :sha256 | :sha512) :: :sha | :sha256 | :sha512
  defp crypto_hash(:sha1), do: :sha
  defp crypto_hash(:sha256), do: :sha256
  defp crypto_hash(:sha512), do: :sha512

  @spec algorithm_name(:sha1 | :sha256 | :sha512) :: String.t()
  defp algorithm_name(:sha1), do: "SHA1"
  defp algorithm_name(:sha256), do: "SHA256"
  defp algorithm_name(:sha512), do: "SHA512"

  @spec parse_algorithm(String.t() | nil) :: :sha1 | :sha256 | :sha512
  defp parse_algorithm(nil), do: :sha1

  defp parse_algorithm(name) do
    case String.upcase(name) do
      "SHA256" -> :sha256
      "SHA512" -> :sha512
      _ -> :sha1
    end
  end

  @spec parse_int(String.t() | nil, integer()) :: integer()
  defp parse_int(nil, default), do: default
  defp parse_int(value, _default), do: String.to_integer(value)

  @spec encode_base32(binary()) :: String.t()
  defp encode_base32(bin) do
    bits = for <<b::1 <- bin>>, do: b

    bits
    |> Enum.chunk_every(5, 5, [])
    |> Enum.map_join("", fn chunk ->
      padded = chunk ++ List.duplicate(0, 5 - length(chunk))
      idx = Enum.reduce(padded, 0, fn bit, acc -> acc * 2 + bit end)
      String.at(@alphabet, idx)
    end)
  end

  @spec decode_base32(String.t()) :: binary()
  defp decode_base32(str) do
    bits =
      str
      |> String.upcase()
      |> String.graphemes()
      |> Enum.flat_map(fn ch ->
        idx = Map.fetch!(@decode_map, ch)
        for <<(b::1 <- <<idx::5>>)>>, do: b
      end)

    bytes =
      bits
      |> Enum.chunk_every(8, 8, :discard)
      |> Enum.map(fn chunk ->
        Enum.reduce(chunk, 0, fn bit, acc -> acc * 2 + bit end)
      end)

    :binary.list_to_bin(bytes)
  end
end
