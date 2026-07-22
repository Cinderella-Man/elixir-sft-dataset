defmodule HOTP do
  @moduledoc """
  RFC 4226 HMAC-based One-Time Passwords (HOTP).

  HOTP is the counter-based sibling of TOTP: each code is derived from a
  monotonically increasing integer counter rather than the wall clock.

  Because a client's counter can run ahead of the server's (the user generated
  codes that were never submitted), validation supports a **forward-only**
  resynchronization window via the `:look_ahead` option. Counters below the
  stored one are never accepted, which prevents replay of already-used codes.

  Implementation notes:

    * secrets are RFC 4648 base32 (uppercase `A–Z`, `2–7`, unpadded);
    * the base32 codec is implemented here rather than pulled from a library;
    * HMAC-SHA1 is computed with `:crypto.mac/4`;
    * codes are 6 digits, zero-padded on the left.

  Only the OTP standard library is used.

      iex> secret = HOTP.generate_secret()
      iex> code = HOTP.generate_code(secret, 7)
      iex> HOTP.valid?(secret, code, 7)
      {:ok, 8}
  """

  @alphabet ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  @secret_bytes 20
  @digits 6
  @modulus 1_000_000

  @doc """
  Generates a cryptographically random secret.

  Returns 160 bits (20 bytes) of entropy from `:crypto.strong_rand_bytes/1`,
  base32-encoded without padding, which is always a 32-character string.

      iex> secret = HOTP.generate_secret()
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
  Generates the 6-digit code for `secret` at the given non-negative `counter`.

  The counter is encoded as a big-endian 64-bit integer and HMAC-SHA1'd with the
  base32-decoded secret. RFC 4226 §5.3 dynamic truncation then yields a 31-bit
  integer, which is reduced modulo 1_000_000 and left-padded with zeros.

  The same `secret`/`counter` pair always produces the same code.

      iex> HOTP.generate_code("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 0)
      "755224"
      iex> HOTP.generate_code("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", 9)
      "520489"
  """
  @spec generate_code(String.t(), non_neg_integer()) :: String.t()
  def generate_code(secret, counter) when is_binary(secret) and is_integer(counter) and counter >= 0 do
    key = base32_decode!(secret)
    hmac = :crypto.mac(:hmac, :sha, key, <<counter::unsigned-big-integer-size(64)>>)

    hmac
    |> dynamic_truncate()
    |> rem(@modulus)
    |> format_code()
  end

  @doc """
  Validates `code` against `secret` for the stored `counter`.

  Options:

    * `:look_ahead` — non-negative integer (default `0`), how many counters
      **beyond** `counter` to also try.

  Counters `counter, counter + 1, …, counter + look_ahead` are checked in
  ascending order; counters below `counter` are never checked. On a match at
  counter `c`, returns `{:ok, c + 1}` — the next counter the server should
  store, so the used code cannot be replayed. Returns `:error` otherwise.

  `code` may be a string or an integer and is left-padded to 6 digits before
  comparison. The lowest matching counter wins.

      iex> secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
      iex> HOTP.valid?(secret, "254676", 3, look_ahead: 5)
      {:ok, 6}
      iex> HOTP.valid?(secret, "755224", 3, look_ahead: 5)
      :error
  """
  @spec valid?(String.t(), String.t() | integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | :error
  def valid?(secret, code, counter, opts \\ [])
      when is_binary(secret) and is_integer(counter) and counter >= 0 and is_list(opts) do
    look_ahead = Keyword.get(opts, :look_ahead, 0)

    unless is_integer(look_ahead) and look_ahead >= 0 do
      raise ArgumentError, ":look_ahead must be a non-negative integer, got: #{inspect(look_ahead)}"
    end

    normalized = normalize_code(code)

    counter..(counter + look_ahead)//1
    |> Enum.find(fn c -> secure_equal?(generate_code(secret, c), normalized) end)
    |> case do
      nil -> :error
      matched -> {:ok, matched + 1}
    end
  end

  @doc """
  Builds an `otpauth://hotp/` provisioning URI for authenticator apps.

  The label is `issuer:account_name` (both parts URI-encoded) and the query
  carries `secret`, `issuer`, `algorithm=SHA1`, `digits=6` and `counter`.

  Note the `hotp` type: counter-based authenticators require the `counter`
  parameter, unlike the time-based `totp` scheme.

      iex> HOTP.provisioning_uri("ABC234", "Acme Inc", "user@example.com", 0)
      "otpauth://hotp/Acme%20Inc:user%40example.com?secret=ABC234&issuer=Acme+Inc" <>
        "&algorithm=SHA1&digits=6&counter=0"
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), non_neg_integer()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, counter)
      when is_binary(secret) and is_binary(issuer) and is_binary(account_name) and
             is_integer(counter) and counter >= 0 do
    label = "#{encode_label(issuer)}:#{encode_label(account_name)}"

    query =
      URI.encode_query(%{
        "secret" => secret,
        "issuer" => issuer,
        "algorithm" => "SHA1",
        "digits" => Integer.to_string(@digits),
        "counter" => Integer.to_string(counter)
      })

    "otpauth://hotp/" <> label <> "?" <> query
  end

  # --- RFC 4226 §5.3 dynamic truncation -------------------------------------

  @spec dynamic_truncate(binary()) :: non_neg_integer()
  defp dynamic_truncate(hmac) do
    offset = :binary.last(hmac) &&& 0x0F
    <<_skip::binary-size(offset), truncated::binary-size(4), _rest::binary>> = hmac
    <<value::unsigned-big-integer-size(32)>> = truncated
    value &&& 0x7FFF_FFFF
  end

  import Bitwise, only: [&&&: 2, |||: 2, <<<: 2, >>>: 2]

  # --- code helpers ---------------------------------------------------------

  @spec format_code(non_neg_integer()) :: String.t()
  defp format_code(number) do
    number
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @spec normalize_code(String.t() | integer()) :: String.t()
  defp normalize_code(code) when is_integer(code) and code >= 0, do: format_code(code)

  defp normalize_code(code) when is_binary(code) do
    code
    |> String.trim()
    |> String.pad_leading(@digits, "0")
  end

  # Constant-time comparison to avoid leaking match position via timing.
  @spec secure_equal?(binary(), binary()) :: boolean()
  defp secure_equal?(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end

  defp secure_equal?(_a, _b), do: false

  # --- RFC 4648 base32 ------------------------------------------------------

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) when is_binary(binary) do
    bits = bit_size(binary)
    padding = rem(5 - rem(bits, 5), 5)

    <<padded::bitstring>> = <<binary::bitstring, 0::size(padding)>>

    for <<chunk::5 <- padded>>, into: "" do
      <<Enum.at(@alphabet, chunk)>>
    end
  end

  @spec base32_decode!(String.t()) :: binary()
  defp base32_decode!(secret) when is_binary(secret) do
    secret
    |> String.upcase()
    |> String.replace("=", "")
    |> to_charlist()
    |> Enum.reduce({0, 0, <<>>}, fn char, {acc, bits, out} ->
      value = char_value!(char)
      acc = (acc <<< 5) ||| value
      bits = bits + 5

      if bits >= 8 do
        byte = acc >>> (bits - 8) &&& 0xFF
        {acc, bits - 8, <<out::binary, byte>>}
      else
        {acc, bits, out}
      end
    end)
    |> elem(2)
  end

  @spec char_value!(char()) :: non_neg_integer()
  defp char_value!(char) do
    case Enum.find_index(@alphabet, &(&1 == char)) do
      nil -> raise ArgumentError, "invalid base32 character: #{inspect(<<char>>)}"
      index -> index
    end
  end
end