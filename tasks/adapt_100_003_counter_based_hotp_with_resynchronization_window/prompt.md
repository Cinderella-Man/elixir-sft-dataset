# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

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

  defp base32_encode(data) when is_binary(data), do: encode_groups(data, <<>>)

  # Consume 5 bytes (40 bits) at a time, emit 8 characters.
  defp encode_groups(
         <<a::5, b::5, c::5, d::5, e::5, f::5, g::5, h::5, rest::binary>>,
         acc
       ) do
    chunk = <<enc(a), enc(b), enc(c), enc(d), enc(e), enc(f), enc(g), enc(h)>>
    encode_groups(rest, <<acc::binary, chunk::binary>>)
  end

  defp encode_groups(<<>>, acc), do: acc

  # 1–4 byte remainder: right-pad with zero bits to a 5-bit boundary, then emit.
  defp encode_groups(rest, acc) when is_binary(rest) do
    pad = rem(5 - rem(bit_size(rest), 5), 5)
    encode_tail(<<rest::bitstring, 0::size(pad)>>, acc)
  end

  defp encode_tail(<<>>, acc), do: acc

  defp encode_tail(<<x::5, rest::bitstring>>, acc),
    do: encode_tail(rest, <<acc::binary, enc(x)>>)

  defp enc(i) when i in 0..25, do: ?A + i
  defp enc(i) when i in 26..31, do: ?2 + (i - 26)

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

## New specification

Write me an Elixir module called `HOTP` that implements RFC 4226 **HMAC-based** One-Time Passwords — the counter-based sibling of TOTP. Unlike a time-based scheme, each code is tied to a monotonically increasing integer counter rather than the wall clock, and validation must support a **forward-only resynchronization window** because a client's counter can run ahead of the server's (e.g. the user generated codes that were never submitted). Use only the OTP standard library — no external dependencies.

I need these functions in the public API:

- `HOTP.generate_secret()` returns a cryptographically random, base32-encoded secret string (160 bits / 20 bytes of entropy, no padding characters), producing a 32-character string. It must use `:crypto.strong_rand_bytes/1`.

- `HOTP.generate_code(secret, counter)` returns a 6-digit zero-padded string for the given non-negative integer `counter`. It HMAC-SHA1s the counter (encoded as a big-endian 8-byte integer) with the base32-decoded secret, applies the RFC 4226 dynamic truncation, and takes the result modulo 1_000_000. The same counter with the same secret must always produce the same code. It must reproduce the RFC 4226 Appendix D test vectors for the seed `"12345678901234567890"`: counters 0 through 9 yield `755224`, `287082`, `359152`, `969429`, `338314`, `254676`, `287922`, `162583`, `399871`, `520489`.

- `HOTP.valid?(secret, code, counter, opts \\ [])` validates a `code` (string or integer) against a stored `counter`. Options:
  - `:look_ahead` — a non-negative integer (default `0`) giving how many additional counters **beyond** `counter` to try.

  Validation checks the counters `counter, counter + 1, …, counter + look_ahead` in ascending order. This is **forward-only**: counters below `counter` are never checked. If the code matches at some counter `c`, return `{:ok, c + 1}` (the next counter the server should store so the used code cannot be replayed). If no counter in the range matches, return `:error`. The code is normalized by left-padding to 6 digits before comparison. When multiple counters would match, the first (lowest) match wins.

- `HOTP.provisioning_uri(secret, issuer, account_name, counter)` returns an `otpauth://hotp/` URI (note: `hotp`, not `totp`, since HOTP authenticators require a counter). The label is `issuer:account_name` with both parts URI-encoded. The query parameters are `secret`, `issuer`, `algorithm=SHA1`, `digits=6`, and `counter` (the given integer). All parameters must be properly URI-encoded.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7, unpadded). Implement it yourself rather than relying on a library.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation (RFC 4226 §5.3): take the last byte of the HMAC, mask with `0x0F` to get the offset, read 4 bytes from that offset, mask the top bit of the first byte with `0x7F`, then take the resulting 31-bit integer modulo 1_000_000.
- Generated codes must always be exactly 6 characters, left-padded with zeros if necessary.

Give me the complete module in a single file.
