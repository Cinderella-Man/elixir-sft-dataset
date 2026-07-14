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

Write me an Elixir module called `TOTPVault` that is a `GenServer` managing per-account TOTP secrets and validating codes with **replay protection**, using only the OTP standard library — no external dependencies.

The point of this variant is state and concurrency: a single server process holds every account's secret and the highest 30-second step that has already been "spent." Once a code for a given step is consumed, that same code (and any code for an earlier step) can never be accepted again, even under concurrent submissions.

Codes are standard RFC 6238: base32 secret (160 bits / 20 random bytes, no padding, generated with `:crypto.strong_rand_bytes/1`), HMAC-SHA1 over the big-endian 8-byte step `div(time, 30)`, RFC 4226 dynamic truncation, modulo 1_000_000, left-padded to a 6-character string.

I need these functions in the public API:

- `TOTPVault.start_link(opts \\ [])` starts the server and returns `{:ok, pid}`. It accepts a standard `:name` option for registering the process.
- `TOTPVault.register(server, account_id)` generates a fresh secret for `account_id`, stores it, and returns `{:ok, secret}` (the base32 secret string). If `account_id` is already registered, it returns `{:error, :already_registered}` and does not change the stored secret.
- `TOTPVault.secret(server, account_id)` returns `{:ok, secret}` for a registered account, or `{:error, :not_found}`.
- `TOTPVault.current_code(server, account_id, opts \\ [])` returns `{:ok, code}` — the 6-digit code for the account at the given time — or `{:error, :not_found}`. It accepts a `:time` option (UNIX seconds, default: current time). This function is read-only: it never consumes anything.
- `TOTPVault.consume(server, account_id, code, opts \\ [])` validates and, on success, spends a code. Options:
  - `:time` — UNIX seconds (default: current time)
  - `:window` — number of 30-second steps accepted in each direction (default: `1`)

  Let `base = div(time, 30)`. Consider the steps `base - window .. base + window` (only those `>= 0`). Behavior:
  - If `account_id` is not registered, return `{:error, :not_found}`.
  - If `code` (accepted as a string or integer) does not match the code for any step in the window, return `{:error, :invalid}`.
  - If `code` matches a step in the window, let `matched` be that step. If the account already has a consumed step `last` and `matched <= last`, return `{:error, :replayed}` and do not change stored state.
  - Otherwise (a match with `matched` greater than any previously consumed step, or no prior consumption), record `matched` as the account's new highest consumed step and return `:ok`.

Concurrency requirement: because the server processes messages one at a time, if several callers submit the *same* valid code concurrently, exactly one `consume/4` call returns `:ok` and every other returns `{:error, :replayed}`.

Requirements and constraints:
- Base32 encoding/decoding must follow RFC 4648 (uppercase alphabet A–Z, 2–7, unpadded). Implement it yourself.
- HMAC-SHA1 must be done via Erlang's `:crypto.mac/4`.
- Dynamic truncation: last byte masked with `0x0F` is the offset; read 4 bytes from that offset; mask the top bit with `0x7F`; take modulo 1_000_000.
- Generated codes are always exactly 6 characters, zero-padded.

Give me the complete module in a single file.
