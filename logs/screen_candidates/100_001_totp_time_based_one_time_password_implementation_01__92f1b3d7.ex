defmodule TOTP do
  @moduledoc """
  RFC 6238 Time-Based One-Time Passwords (TOTP) built on the OTP standard library.

  This module implements the full TOTP flow with no external dependencies:

    * `generate_secret/0` — a cryptographically random, base32-encoded shared secret.
    * `generate_code/2` — a 6-digit code for a given UNIX timestamp.
    * `valid?/3` — validation of a code with a configurable clock-drift window.
    * `provisioning_uri/3` — an `otpauth://totp/` URI for authenticator apps.

  The parameters are fixed to the values that authenticator applications expect:
  HMAC-SHA1, 6 digits, and a 30-second period. Base32 encoding follows RFC 4648
  (uppercase alphabet `A-Z` plus `2-7`) and is implemented here rather than pulled in
  from a library.

  ## Examples

      secret = TOTP.generate_secret()
      code = TOTP.generate_code(secret)
      true = TOTP.valid?(secret, code)

  """

  @base32_alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  @secret_bytes 20
  @period 30
  @digits 6
  @modulo 1_000_000
  @default_window 1

  @doc """
  Generates a cryptographically random secret, base32-encoded without padding.

  The secret carries 160 bits (20 bytes) of entropy, as recommended by RFC 4226,
  and is produced with `:crypto.strong_rand_bytes/1`.

  ## Examples

      iex> secret = TOTP.generate_secret()
      iex> String.length(secret)
      32

  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Generates the 6-digit TOTP code for `secret` at `time` (UNIX seconds).

  The time step is `div(time, 30)`. That step is HMAC-SHA1'd — as a big-endian
  8-byte integer — with the base32-decoded `secret`, dynamically truncated per
  RFC 4226, reduced modulo 1_000_000, and zero-padded to exactly six characters.

  ## Examples

      iex> TOTP.generate_code("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 59)
      "287082"

  """
  @spec generate_code(String.t(), integer()) :: String.t()
  def generate_code(secret, time \\ :os.system_time(:second))
      when is_binary(secret) and is_integer(time) do
    secret
    |> base32_decode!()
    |> hotp(div(time, @period))
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @doc """
  Checks `code` against `secret`, tolerating clock drift.

  `code` may be a string (zero-padded or not) or an integer.

  ## Options

    * `:time` — the UNIX timestamp in seconds to validate against. Defaults to now.
    * `:window` — the number of 30-second steps to check in each direction. Defaults
      to `1`, which tolerates a drift of up to ±30 seconds.

  Returns `true` when `code` matches the code of any step in the window, `false`
  otherwise. Comparison is constant-time with respect to the code contents.

  ## Examples

      iex> secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
      iex> TOTP.valid?(secret, "287082", time: 59)
      true
      iex> TOTP.valid?(secret, "000000", time: 59, window: 0)
      false

  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ [])

  def valid?(secret, code, opts) when is_binary(secret) and is_integer(code) do
    valid?(secret, code |> Integer.to_string() |> String.pad_leading(@digits, "0"), opts)
  end

  def valid?(secret, code, opts) when is_binary(secret) and is_binary(code) do
    time = Keyword.get(opts, :time, :os.system_time(:second))
    window = Keyword.get(opts, :window, @default_window)

    with true <- is_integer(time),
         true <- is_integer(window) and window >= 0,
         {:ok, key} <- base32_decode(secret) do
      step = div(time, @period)

      Enum.reduce(-window..window//1, false, fn offset, acc ->
        candidate =
          key
          |> hotp(step + offset)
          |> Integer.to_string()
          |> String.pad_leading(@digits, "0")

        secure_compare(candidate, code) or acc
      end)
    else
      _other -> false
    end
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI for authenticator applications.

  The label is `issuer:account_name` and the query carries `secret`, `issuer`,
  `algorithm=SHA1`, `digits=6`, and `period=30`. Every component is URI-encoded.

  ## Examples

      iex> TOTP.provisioning_uri("JBSWY3DPEHPK3PXP", "Acme Corp", "alice@example.com")
      "otpauth://totp/Acme%20Corp:alice%40example.com?secret=JBSWY3DPEHPK3PXP" <>
        "&issuer=Acme%20Corp&algorithm=SHA1&digits=6&period=30"

  """
  @spec provisioning_uri(String.t(), String.t(), String.t()) :: String.t()
  def provisioning_uri(secret, issuer, account_name)
      when is_binary(secret) and is_binary(issuer) and is_binary(account_name) do
    label = encode(issuer) <> ":" <> encode(account_name)

    query =
      URI.encode_query(
        [
          {"secret", secret},
          {"issuer", issuer},
          {"algorithm", "SHA1"},
          {"digits", Integer.to_string(@digits)},
          {"period", Integer.to_string(@period)}
        ],
        :rfc3986
      )

    "otpauth://totp/" <> label <> "?" <> query
  end

  ## Internal helpers

  @spec encode(String.t()) :: String.t()
  defp encode(value), do: URI.encode(value, &URI.char_unreserved?/1)

  @spec hotp(binary(), integer()) :: non_neg_integer()
  defp hotp(key, step) do
    hmac = :crypto.mac(:hmac, :sha, key, <<step::unsigned-big-integer-size(64)>>)
    <<_rest::binary-size(19), _high::4, offset::4>> = hmac
    <<_skip::binary-size(offset), _mask::1, truncated::31, _tail::binary>> = hmac
    rem(truncated, @modulo)
  end

  @spec secure_compare(binary(), binary()) :: boolean()
  defp secure_compare(left, right) when byte_size(left) == byte_size(right) do
    :crypto.hash_equals(left, right)
  end

  defp secure_compare(_left, _right), do: false

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) when is_binary(binary) do
    for <<chunk::5 <- pad_bits(binary)>>, into: "" do
      <<Enum.at(@base32_alphabet, chunk)>>
    end
  end

  @spec pad_bits(binary()) :: bitstring()
  defp pad_bits(binary) do
    case rem(bit_size(binary), 5) do
      0 -> binary
      remainder -> <<binary::bitstring, 0::size(5 - remainder)>>
    end
  end

  @spec base32_decode!(String.t()) :: binary()
  defp base32_decode!(secret) do
    case base32_decode(secret) do
      {:ok, binary} -> binary
      :error -> raise ArgumentError, "invalid base32 secret: #{inspect(secret)}"
    end
  end

  @spec base32_decode(String.t()) :: {:ok, binary()} | :error
  defp base32_decode(secret) when is_binary(secret) do
    secret
    |> String.upcase()
    |> String.replace("=", "")
    |> String.to_charlist()
    |> decode_chars(<<>>)
  end

  @spec decode_chars(charlist(), bitstring()) :: {:ok, binary()} | :error
  defp decode_chars([], acc) do
    bits = bit_size(acc)
    usable = div(bits, 8) * 8
    <<binary::binary-size(div(usable, 8)), remainder::bitstring>> = acc

    if leftover_is_padding?(remainder), do: {:ok, binary}, else: :error
  end

  defp decode_chars([char | rest], acc) do
    case Enum.find_index(@base32_alphabet, &(&1 == char)) do
      nil -> :error
      value -> decode_chars(rest, <<acc::bitstring, value::5>>)
    end
  end

  @spec leftover_is_padding?(bitstring()) :: boolean()
  defp leftover_is_padding?(remainder) when bit_size(remainder) < 5 do
    size = bit_size(remainder)
    <<value::size(size)>> = remainder
    value == 0
  end

  defp leftover_is_padding?(_remainder), do: false
end