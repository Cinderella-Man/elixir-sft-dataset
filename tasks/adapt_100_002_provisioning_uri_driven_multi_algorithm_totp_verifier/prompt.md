# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

Write me an Elixir module called `AuthenticatorURI` that goes the *other* direction from a normal TOTP generator: instead of building an `otpauth://` provisioning URI, it **parses** one into a validated configuration and then generates/verifies codes from that configuration. Use only the OTP standard library — no external dependencies.

The point of the module is that authenticator apps must accept whatever the server put in the QR code: SHA1/SHA256/SHA512, 6/7/8 digits, and periods other than 30 seconds. So all OTP parameters come from the URI, not from hard-coded constants.

## Public API

### `AuthenticatorURI.parse(uri)`

Takes an `otpauth://totp/...` URI string and returns `{:ok, config}` or `{:error, reason}` where `reason` is an atom.

`config` is a map with exactly these keys:

- `:issuer` — `String.t()` or `nil`
- `:account` — `String.t()`
- `:secret` — `String.t()` (normalized base32, see below)
- `:algorithm` — `:sha1`, `:sha256`, or `:sha512`
- `:digits` — integer, one of `6`, `7`, `8`
- `:period` — positive integer (seconds)

Parsing rules:

- **Scheme.** The scheme must be `otpauth` (compare case-insensitively). Anything else — and any non-binary argument — returns `{:error, :invalid_scheme}`.
- **Type.** The URI host is the OTP type. It must be `totp` (case-insensitive). `hotp` or anything else returns `{:error, :unsupported_type}`.
- **Label.** The path (with its leading `/` removed) is the percent-encoded label. Decode it with `URI.decode/1`. It is either `Issuer:Account` or just `Account`. A single optional space immediately after the colon is allowed and must be stripped from the account. An empty label, an empty issuer part, or an empty account part returns `{:error, :missing_label}`.
- **Query parameters.** Decode with `URI.decode_query/1` (so `+` means space).
  - `secret` (required). Strip all whitespace and `=` padding characters, then upcase. After that it must be a non-empty string of RFC 4648 base32 characters (`A`–`Z`, `2`–`7`); the normalized string is what goes into `config.secret`. A missing `secret` returns `{:error, :missing_secret}`; a secret with any other character (or one that normalizes to the empty string) returns `{:error, :invalid_secret}`.
  - `issuer` (optional). If the label carries an issuer and the `issuer` parameter is also present, they must be equal — otherwise return `{:error, :issuer_mismatch}`. If only one of them is present, that one is the issuer. If neither is present, `config.issuer` is `nil`.
  - `algorithm` (optional, default `SHA1`). Case-insensitive; `SHA1` → `:sha1`, `SHA256` → `:sha256`, `SHA512` → `:sha512`. Anything else returns `{:error, :unsupported_algorithm}`.
  - `digits` (optional, default `6`). Must be the exact decimal string of `6`, `7`, or `8`; anything else (including non-numeric text or trailing garbage) returns `{:error, :invalid_digits}`.
  - `period` (optional, default `30`). Must be the exact decimal string of a positive integer; zero, negative, or non-numeric values return `{:error, :invalid_period}`.

### `AuthenticatorURI.code_at(config, unix_time)`

Returns the OTP code for a parsed `config` at the given UNIX timestamp (seconds), as a zero-padded string of exactly `config.digits` characters.

Algorithm (RFC 6238 / RFC 4226):

1. `step = div(unix_time, config.period)`, encoded as a big-endian unsigned 64-bit integer.
2. HMAC that counter with the base32-decoded secret using `:crypto.mac(:hmac, hash, key, counter)`, where `hash` is `:sha`, `:sha256`, or `:sha512` according to `config.algorithm`.
3. Dynamic truncation: take the low 4 bits of the **last** byte of the HMAC as an offset, read the 4 bytes at that offset, mask the top bit of the first of them with `0x7F`, and interpret them big-endian.
4. Take the result modulo `10 ^ config.digits` and zero-pad on the left to `config.digits` characters.

You must implement RFC 4648 base32 **decoding** yourself (uppercase alphabet `A`–`Z` plus `2`–`7`, no padding; leftover bits that do not complete a byte are discarded). Do not use an external library.

### `AuthenticatorURI.seconds_remaining(config, unix_time)`

Returns `config.period - rem(unix_time, config.period)` — i.e. the number of seconds the current code stays valid. On an exact period boundary this returns the full period.

### `AuthenticatorURI.verify(config, code, unix_time)`

Returns `true` if `code` matches the code for the *exact* current step, `false` otherwise. There is **no** drift window: a code from the previous or next step must be rejected. `code` may be a string or an integer; normalize it by converting to a string and zero-padding on the left to `config.digits` characters, then compare against `code_at/2` using a constant-time (non-short-circuiting) byte comparison.

Give me the complete module in a single file.
