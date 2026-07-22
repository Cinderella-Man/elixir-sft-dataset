Implement the private `base32_encode/1` function.

It takes a binary and returns its RFC 4648 base32 representation as a binary
string, using the uppercase alphabet `A`–`Z` followed by the digits `2`–`7`,
with **no** `=` padding characters.

Behaviour:

- Process the input 5 bytes (40 bits) at a time, splitting each group into eight
  5-bit chunks and emitting one alphabet character per chunk (so 5 input bytes →
  8 output characters).
- For a trailing remainder of 1–4 bytes, right-pad the leftover bits with zero
  bits up to the next 5-bit boundary, then emit one character per 5-bit chunk.
  Do not append `=` padding.
- An empty binary encodes to an empty string.
- The 20-byte secrets used by `generate_secret/0` therefore encode to exactly
  32 characters.

You may add private helper functions (e.g. for the group/tail recursion and for
mapping a 5-bit integer to its alphabet character). Every other function in the
module is already written — do not change them.

```elixir
defmodule TOTP do
  @moduledoc """
  RFC 6238 Time-Based One-Time Password (TOTP) implementation.

  Produces 6-digit HMAC-SHA1 codes with a 30-second period, compatible with
  Google Authenticator, Authy, 1Password, and other RFC 6238 authenticators.

  Uses only Erlang/OTP and Elixir standard libraries — no external dependencies.
  """

  import Bitwise

  @period 30
  @digits 6
  @secret_bytes 20

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Generates a cryptographically random, base32-encoded 160-bit secret
  (20 bytes → 32 characters, no padding).
  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end

  @doc """
  Returns the 6-digit TOTP code for `secret` at the given UNIX timestamp.
  """
  @spec generate_code(String.t(), integer()) :: String.t()
  def generate_code(secret, time \\ :os.system_time(:second)) do
    key = base32_decode!(secret)
    step = div(time, @period)
    counter = <<step::big-unsigned-integer-size(64)>>

    :hmac
    |> :crypto.mac(:sha, key, counter)
    |> dynamic_truncate()
    |> rem(1_000_000)
    |> Integer.to_string()
    |> String.pad_leading(@digits, "0")
  end

  @doc """
  Validates `code` against `secret`, tolerating clock drift.

  ## Options

    * `:time`   — UNIX seconds to validate against (default: current time)
    * `:window` — number of 30-second steps accepted in each direction (default: 1)
  """
  @spec valid?(String.t(), String.t() | integer(), keyword()) :: boolean()
  def valid?(secret, code, opts \\ []) do
    time = Keyword.get(opts, :time, :os.system_time(:second))
    window = Keyword.get(opts, :window, 1)
    expected = normalize_code(code)

    Enum.any?(-window..window, fn offset ->
      t = time + offset * @period
      secure_equal?(generate_code(secret, t), expected)
    end)
  end

  @doc """
  Builds an `otpauth://totp/` provisioning URI for authenticator apps.

  The label is `issuer:account_name` (both URI-encoded); query parameters
  include `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, `period=30`.
  """
  @spec provisioning_uri(String.t(), String.t(), String.t()) :: String.t()
  def provisioning_uri(secret, issuer, account_name) do
    label =
      URI.encode(issuer, &URI.char_unreserved?/1) <>
        ":" <> URI.encode(account_name, &URI.char_unreserved?/1)

    query =
      URI.encode_query([
        {"secret", secret},
        {"issuer", issuer},
        {"algorithm", "SHA1"},
        {"digits", Integer.to_string(@digits)},
        {"period", Integer.to_string(@period)}
      ])

    "otpauth://totp/" <> label <> "?" <> query
  end

  # ---------------------------------------------------------------------------
  # Dynamic truncation (RFC 4226 §5.3)
  # ---------------------------------------------------------------------------

  defp dynamic_truncate(<<_::binary-size(19), last::8>> = hmac) do
    offset = last &&& 0x0F
    <<_::binary-size(^offset), b0, b1, b2, b3, _::binary>> = hmac

    (b0 &&& 0x7F) <<< 24 ||| b1 <<< 16 ||| b2 <<< 8 ||| b3
  end

  # ---------------------------------------------------------------------------
  # Base32 (RFC 4648, uppercase A–Z + 2–7, unpadded)
  # ---------------------------------------------------------------------------

  # --- encode ---

  defp base32_encode(data) when is_binary(data) do
    # TODO
  end

  # --- decode ---

  defp base32_decode!(str) when is_binary(str) do
    bits = decode_bits(String.upcase(str), <<>>)
    byte_count = div(bit_size(bits), 8)
    <<bytes::binary-size(^byte_count), _::bitstring>> = bits
    bytes
  end

  defp decode_bits(<<>>, acc), do: acc

  defp decode_bits(<<c, rest::binary>>, acc),
    do: decode_bits(rest, <<acc::bitstring, dec!(c)::5>>)

  defp dec!(c) when c in ?A..?Z, do: c - ?A
  defp dec!(c) when c in ?2..?7, do: c - ?2 + 26
  defp dec!(c), do: raise(ArgumentError, "invalid base32 character: #{<<c>>}")

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp normalize_code(code) when is_integer(code),
    do: code |> Integer.to_string() |> String.pad_leading(@digits, "0")

  defp normalize_code(code) when is_binary(code),
    do: String.pad_leading(code, @digits, "0")

  # Constant-time string compare — avoids leaking match position via timing.
  defp secure_equal?(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> acc ||| bxor(x, y) end)
    |> Kernel.==(0)
  end

  defp secure_equal?(_, _), do: false
end
```