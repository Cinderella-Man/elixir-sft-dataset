defmodule HOTP do
  @moduledoc """
  RFC 4226 HMAC-Based (counter-based) One-Time Passwords.

  HOTP codes are driven by a monotonically increasing counter that both the
  client and server advance on each successful authentication. Because a
  client's counter can run ahead of the server's (for example, a token button
  pressed without a successful login), servers validate with a bounded
  look-ahead window and resynchronize to whichever counter actually matched.

  This module depends only on the OTP standard library (`:crypto`). Base32
  encoding and decoding follow RFC 4648 (uppercase `A`–`Z`, `2`–`7`, no
  padding) and are implemented here rather than pulled from a dependency.
  """

  import Bitwise

  @digits 6
  @modulo 1_000_000
  @secret_bytes 20

  @base32_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @base32_decode_table @base32_alphabet
                       |> String.to_charlist()
                       |> Enum.with_index()
                       |> Map.new()

  @typedoc "A base32-encoded (RFC 4648, unpadded) shared secret."
  @type secret :: String.t()

  @doc """
  Generates a cryptographically random, base32-encoded secret.

  The secret carries 160 bits (20 bytes) of entropy sourced from
  `:crypto.strong_rand_bytes/1` and is returned unpadded.
  """
  @spec generate_secret() :: secret()
  def generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Generates the 6-digit, zero-padded HOTP code for `counter`.

  The `counter` must be a non-negative integer. It is HMAC-SHA1'd (encoded as
  a big-endian 8-byte integer) with the base32-decoded `secret`, run through
  the RFC 4226 dynamic truncation, and reduced modulo 1_000_000.
  """
  @spec generate_code(secret(), non_neg_integer()) :: String.t()
  def generate_code(secret, counter)
      when is_binary(secret) and is_integer(counter) and counter >= 0 do
    key = base32_decode(secret)
    message = <<counter::unsigned-big-integer-size(64)>>
    hmac = :crypto.mac(:hmac, :sha, key, message)

    hmac
    |> dynamic_truncate()
    |> rem(@modulo)
    |> pad_code()
  end

  @doc """
  Validates `code` against `secret` over a look-ahead window.

  `code` may be a string or a non-negative integer. The `:look_ahead` option
  (a non-negative integer, default `0`) gives how many additional counters
  *after* `counter` to also accept. Returns `true` when `code` matches the
  code for any counter in the inclusive range `counter..(counter +
  look_ahead)`, otherwise `false`.
  """
  @spec valid?(secret(), String.t() | non_neg_integer(), non_neg_integer(), keyword()) ::
          boolean()
  def valid?(secret, code, counter, opts \\ []) do
    look_ahead = fetch_look_ahead(opts, 0)
    normalized = normalize_code(code)

    Enum.any?(counter..(counter + look_ahead), fn candidate ->
      secure_equal?(generate_code(secret, candidate), normalized)
    end)
  end

  @doc """
  Performs resynchronizing validation of `code` against `secret`.

  The `:look_ahead` option (a non-negative integer, default `3`) bounds the
  search window. Scanning counters in ascending order across the inclusive
  range `counter..(counter + look_ahead)`, this returns `{:ok, matched + 1}`
  for the first counter whose code matches — the next counter the server
  should store — or `:error` when no counter in the range matches.
  """
  @spec verify(secret(), String.t() | non_neg_integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | :error
  def verify(secret, code, counter, opts \\ []) do
    look_ahead = fetch_look_ahead(opts, 3)
    normalized = normalize_code(code)

    counter..(counter + look_ahead)
    |> Enum.find(fn candidate ->
      secure_equal?(generate_code(secret, candidate), normalized)
    end)
    |> case do
      nil -> :error
      matched -> {:ok, matched + 1}
    end
  end

  @doc """
  Builds an `otpauth://hotp/` provisioning URI.

  The label is `issuer:account_name` (both URI-encoded), and the query string
  carries `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and
  `counter=<counter>`, all properly URI-encoded.
  """
  @spec provisioning_uri(secret(), String.t(), String.t(), non_neg_integer()) :: String.t()
  def provisioning_uri(secret, issuer, account_name, counter) do
    label = uri_encode(issuer) <> ":" <> uri_encode(account_name)

    query =
      [
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"counter", Integer.to_string(counter)}
      ]
      |> Enum.map_join("&", fn {key, value} ->
        uri_encode(key) <> "=" <> uri_encode(value)
      end)

    "otpauth://hotp/" <> label <> "?" <> query
  end

  # --- Internal helpers -----------------------------------------------------

  @spec fetch_look_ahead(keyword(), non_neg_integer()) :: non_neg_integer()
  defp fetch_look_ahead(opts, default) do
    case Keyword.get(opts, :look_ahead, default) do
      value when is_integer(value) and value >= 0 -> value
      _ -> default
    end
  end

  @spec normalize_code(String.t() | integer()) :: String.t()
  defp normalize_code(code) when is_integer(code), do: pad_code(code)
  defp normalize_code(code) when is_binary(code), do: code

  @spec pad_code(integer()) :: String.t()
  defp pad_code(number) do
    number
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @spec dynamic_truncate(binary()) :: non_neg_integer()
  defp dynamic_truncate(hmac) do
    offset = :binary.last(hmac) &&& 0x0F
    <<_::binary-size(offset), slice::unsigned-big-integer-size(32), _::binary>> = hmac
    slice &&& 0x7FFFFFFF
  end

  @spec secure_equal?(binary(), binary()) :: boolean()
  defp secure_equal?(left, right) do
    byte_size(left) == byte_size(right) and constant_time_compare(left, right, 0) == 0
  end

  @spec constant_time_compare(binary(), binary(), non_neg_integer()) :: non_neg_integer()
  defp constant_time_compare(<<a, rest_a::binary>>, <<b, rest_b::binary>>, acc) do
    constant_time_compare(rest_a, rest_b, acc ||| bxor(a, b))
  end

  defp constant_time_compare(<<>>, <<>>, acc), do: acc

  # --- Base32 (RFC 4648, unpadded) ------------------------------------------

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) do
    binary
    |> encode_chunks()
    |> IO.iodata_to_binary()
  end

  @spec encode_chunks(binary()) :: iodata()
  defp encode_chunks(<<>>), do: []

  defp encode_chunks(<<a, b, c, d, e, rest::binary>>) do
    <<i1::5, i2::5, i3::5, i4::5, i5::5, i6::5, i7::5, i8::5>> = <<a, b, c, d, e>>
    [encode_symbols([i1, i2, i3, i4, i5, i6, i7, i8]) | encode_chunks(rest)]
  end

  defp encode_chunks(rest) do
    pad_bits = (5 - rem(byte_size(rest), 5)) * 8

    <<i1::5, i2::5, i3::5, i4::5, i5::5, i6::5, i7::5, i8::5>> =
      <<rest::binary, 0::size(pad_bits)>>

    keep =
      case byte_size(rest) do
        1 -> 2
        2 -> 4
        3 -> 5
        _ -> 7
      end

    [i1, i2, i3, i4, i5, i6, i7, i8] |> Enum.take(keep) |> encode_symbols()
  end

  @spec encode_symbols([non_neg_integer()]) :: [binary()]
  defp encode_symbols(indices) do
    Enum.map(indices, fn index ->
      binary_part(@base32_alphabet, index, 1)
    end)
  end

  @spec base32_decode(secret()) :: binary()
  defp base32_decode(secret) do
    bits =
      secret
      |> String.upcase()
      |> String.to_charlist()
      |> Enum.reduce(<<>>, fn char, acc ->
        <<acc::bitstring, Map.fetch!(@base32_decode_table, char)::5>>
      end)

    byte_count = div(bit_size(bits), 8)
    <<decoded::binary-size(byte_count), _rest::bitstring>> = bits
    decoded
  end

  # --- URI encoding ---------------------------------------------------------

  @spec uri_encode(String.t()) :: String.t()
  defp uri_encode(value) do
    URI.encode(value, &URI.char_unreserved?/1)
  end
end
