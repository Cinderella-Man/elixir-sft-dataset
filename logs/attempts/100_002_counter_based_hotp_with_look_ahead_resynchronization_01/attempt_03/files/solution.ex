defmodule HOTP do
  @moduledoc """
  RFC 4226 HMAC-Based One-Time Passwords (HOTP).

  HOTP is the *event/counter-based* one-time password scheme. Codes are
  indexed by a monotonically increasing integer counter rather than by
  time. The server tracks the next expected counter for each user; because
  a hardware token can be advanced by the user pressing its button without
  the server observing the resulting code, validation uses a forward-only
  look-ahead window and, on success, reports which counter value to persist
  next.

  This module depends only on the OTP standard library (`:crypto`). Base32
  encoding/decoding follows RFC 4648 and is implemented here rather than
  pulled from a dependency. HMAC-SHA1 is computed via `:crypto.mac/4`.
  """

  import Bitwise

  @base32_alphabet "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

  @base32_decode_map @base32_alphabet
                     |> String.to_charlist()
                     |> Enum.with_index()
                     |> Map.new()

  @digits 6
  @modulo 1_000_000

  @doc """
  Generates a cryptographically random secret.

  Returns a base32-encoded string carrying 160 bits (20 bytes) of entropy
  drawn from `:crypto.strong_rand_bytes/1`. The result contains no padding
  characters.
  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    20
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Generates the 6-digit HOTP code for a base32 `secret` and `counter`.

  The `counter` must be a non-negative integer. It is encoded as a
  big-endian 8-byte unsigned integer, HMAC-SHA1'd with the base32-decoded
  secret, run through the RFC 4226 dynamic truncation, and reduced modulo
  1_000_000. The returned string is always exactly six characters,
  left-padded with zeros when necessary.
  """
  @spec generate_code(String.t(), non_neg_integer()) :: String.t()
  def generate_code(secret, counter)
      when is_binary(secret) and is_integer(counter) and counter >= 0 do
    key = base32_decode(secret)
    message = <<counter::unsigned-big-integer-size(64)>>

    :hmac
    |> :crypto.mac(:sha, key, message)
    |> dynamic_truncation()
    |> rem(@modulo)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @doc """
  Verifies a `code` against a forward window of counters.

  The `code` may be a string or an integer; integers are zero-padded to six
  digits. Options:

    * `:look_ahead` - a non-negative integer (default `3`).

  Counters `counter`, `counter + 1`, …, `counter + look_ahead` are checked
  inclusive, in ascending order. On the first (lowest) matching counter `m`
  this returns `{:ok, m + 1}`, the next counter the caller should persist.
  If no counter in the window matches it returns `:error`. Validation is
  forward-only: counters below `counter` are never checked.
  """
  @spec verify(String.t(), String.t() | integer(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer()} | :error
  def verify(secret, code, counter, opts \\ [])
      when is_binary(secret) and is_integer(counter) and counter >= 0 do
    look_ahead = Keyword.get(opts, :look_ahead, 3)
    expected = normalize_code(code)

    counter
    |> Range.new(counter + look_ahead)
    |> Enum.find_value(:error, fn candidate ->
      if generate_code(secret, candidate) == expected do
        {:ok, candidate + 1}
      end
    end)
  end

  @doc """
  Builds an `otpauth://hotp/` provisioning URI.

  The label is `issuer:account_name` and the query carries `secret`,
  `issuer`, `algorithm=SHA1`, `digits=6`, and `counter=<counter>`, all
  URI-encoded. The `:` separating issuer and account name is kept literal;
  the issuer and account name components are each URI-encoded.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t(), non_neg_integer()) ::
          String.t()
  def provisioning_uri(secret, issuer, account_name, counter)
      when is_binary(secret) and is_binary(issuer) and is_binary(account_name) and
             is_integer(counter) and counter >= 0 do
    encoded_issuer = URI.encode(issuer, &URI.char_unreserved?/1)
    encoded_account = URI.encode(account_name, &URI.char_unreserved?/1)
    label = encoded_issuer <> ":" <> encoded_account

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"counter", Integer.to_string(counter)}
      ])

    "otpauth://hotp/" <> label <> "?" <> query
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec normalize_code(String.t() | integer()) :: String.t()
  defp normalize_code(code) when is_integer(code) do
    code
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  defp normalize_code(code) when is_binary(code), do: code

  @spec dynamic_truncation(binary()) :: non_neg_integer()
  defp dynamic_truncation(hmac) do
    offset = :binary.last(hmac) &&& 0x0F

    <<_::binary-size(offset), slice::binary-size(4), _::binary>> = hmac
    <<value::unsigned-big-integer-size(32)>> = slice

    value &&& 0x7FFF_FFFF
  end

  # --- RFC 4648 base32 -------------------------------------------------------

  @spec base32_encode(binary()) :: String.t()
  defp base32_encode(binary) when is_binary(binary) do
    for <<index::5 <- binary>>, into: "" do
      binary_part(@base32_alphabet, index, 1)
    end
  end

  @spec base32_decode(String.t()) :: binary()
  defp base32_decode(string) when is_binary(string) do
    bits =
      for <<char <- string>>, into: <<>> do
        <<Map.fetch!(@base32_decode_map, char)::5>>
      end

    byte_count = div(bit_size(bits), 8)
    <<bytes::binary-size(byte_count), _::bitstring>> = bits
    bytes
  end
end
