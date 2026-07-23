# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

```elixir
defmodule SecureToken do
  @moduledoc """
  Stateless, signed, expiring tokens backed by HMAC-SHA256.

  Tokens are self-contained: they carry the payload, issue time, and
  expiry time, all covered by a MAC computed with the caller's secret.
  No database or persistent state is required to verify them.

  ## Wire format

  The decoded binary (before base64) has the layout:

      <<issued_at::signed-64, expires_at::signed-64,
        payload_size::unsigned-32, payload::binary, mac::binary-32>>

  where `payload` is `:erlang.term_to_binary/1` output and `mac` is
  `HMAC-SHA256(secret, issued_at || expires_at || payload_size || payload)`.
  The whole thing is then `Base.url_encode64/2` without padding.

  ## Clock injection

  Both `generate/4` and `verify/3` accept an optional `:clock` keyword
  whose value is a zero-arity function returning a Unix epoch second.
  When omitted, `System.os_time(:second)` is used. This is primarily a
  test seam — in production you should let the default apply.
  """

  import Bitwise

  @hmac_size 32

  @type token :: binary()
  @type reason :: :expired | :invalid_signature | :malformed
  @type opts :: [clock: (-> integer())]

  @doc """
  Generate a signed token for `payload` that expires in `ttl_seconds`.
  """
  @spec generate(term(), binary(), pos_integer(), opts()) :: token()
  def generate(payload, secret, ttl_seconds, opts \\ [])
      when is_binary(secret) and is_integer(ttl_seconds) and ttl_seconds > 0 do
    issued_at = now(opts)
    expires_at = issued_at + ttl_seconds
    payload_bytes = :erlang.term_to_binary(payload)
    payload_size = byte_size(payload_bytes)

    data =
      <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32,
        payload_bytes::binary>>

    mac = :crypto.mac(:hmac, :sha256, secret, data)

    Base.url_encode64(<<data::binary, mac::binary>>, padding: false)
  end

  @doc """
  Verify and decode a token.

  Returns `{:ok, payload}` if the signature is valid and the token has not
  expired. Otherwise returns one of:

    * `{:error, :invalid_signature}` — structure is readable, HMAC doesn't match
    * `{:error, :expired}`           — signature is valid, token is past its expiry
    * `{:error, :malformed}`         — bad base64, too short, corrupted structure, etc.

  The signature is always checked before expiry, so a valid-structure but
  wrong-secret token that also happens to be past its expiry returns
  `:invalid_signature`, never `:expired`.
  """
  @spec verify(token(), binary(), opts()) :: {:ok, term()} | {:error, reason()}
  def verify(token, secret, opts \\ [])

  def verify(token, secret, opts) when is_binary(token) and is_binary(secret) do
    with {:ok, decoded} <- decode_base64(token),
         {:ok, data, mac} <- split_mac(decoded),
         {:ok, _issued_at, expires_at, payload_bytes} <- parse_data(data),
         :ok <- verify_mac(secret, data, mac),
         :ok <- check_expiry(expires_at, opts),
         {:ok, payload} <- decode_payload(payload_bytes) do
      {:ok, payload}
    end
  end

  def verify(_token, _secret, _opts), do: {:error, :malformed}

  # --- internal helpers ---------------------------------------------------

  defp now(opts) do
    case Keyword.get(opts, :clock) do
      nil -> System.os_time(:second)
      fun when is_function(fun, 0) -> fun.()
    end
  end

  defp decode_base64(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, binary} -> {:ok, binary}
      :error -> {:error, :malformed}
    end
  end

  # Too short to even contain an HMAC → malformed.
  defp split_mac(binary) when byte_size(binary) < @hmac_size do
    {:error, :malformed}
  end

  defp split_mac(binary) do
    data_size = byte_size(binary) - @hmac_size
    <<data::binary-size(^data_size), mac::binary-size(@hmac_size)>> = binary
    {:ok, data, mac}
  end

  # Structural parse runs before MAC verification so that genuinely
  # corrupted bytes (too-short header, payload_size not matching the
  # remaining binary) come back as :malformed rather than being
  # reported as signature failures. An attacker who knows the key can
  # of course still produce a parseable-but-expired token — but that
  # path is governed by verify_mac/check_expiry, not by this function.
  defp parse_data(
         <<issued_at::signed-64, expires_at::signed-64, payload_size::unsigned-32, rest::binary>>
       )
       when byte_size(rest) == payload_size do
    {:ok, issued_at, expires_at, rest}
  end

  defp parse_data(_), do: {:error, :malformed}

  defp verify_mac(secret, data, mac) do
    expected = :crypto.mac(:hmac, :sha256, secret, data)

    if constant_time_equal?(expected, mac) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  # A token is expired when the current wall-clock time has reached or
  # passed `expires_at`. Strict `<` means that at exactly the TTL
  # boundary (now == issued_at + ttl) the token is already expired.
  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at do
      :ok
    else
      {:error, :expired}
    end
  end

  # [:safe] prevents decoding of terms that could allocate new atoms or
  # function references — standard hygiene for untrusted binaries even
  # after MAC verification.
  defp decode_payload(bytes) do
    {:ok, :erlang.binary_to_term(bytes, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end

  # Constant-time equality check over two equal-length binaries. Avoids
  # short-circuiting on the first differing byte, which would otherwise
  # let a careful attacker probe the MAC one byte at a time.
  defp constant_time_equal?(a, b) when byte_size(a) == byte_size(b) do
    a
    |> :binary.bin_to_list()
    |> Enum.zip(:binary.bin_to_list(b))
    |> Enum.reduce(0, fn {x, y}, acc -> bor(acc, bxor(x, y)) end)
    |> Kernel.==(0)
  end

  defp constant_time_equal?(_, _), do: false
end
```

## New specification

# Specification: `CapabilityToken` — Attenuable Capability Tokens with Chained Caveats

## Overview

This document specifies an Elixir module named `CapabilityToken` that implements **attenuable capability tokens** (macaroon-style): bearer tokens that any holder can *narrow* offline, without the signing key, but that nobody can *widen*.

There is no server, no database, and no stored state. A token is a self-contained binary, and verification is a pure recomputation from the root key.

The deliverable is the complete module in a single file.

## Public API

- `CapabilityToken.mint(root_key, identifier)` — `root_key` is a binary signing key, `identifier` is a binary naming the capability (e.g. `"user:42"`). Returns a URL-safe binary token with zero caveats.

- `CapabilityToken.attenuate(token, caveat)` — appends one caveat to a token **without needing the root key**. `caveat` is a non-empty binary (1..65_535 bytes). Returns `{:ok, new_token}`. Returns `{:error, :malformed}` if `token` is not a decodable token, if `token` or `caveat` is not a binary, or if `caveat` is empty or longer than 65_535 bytes. The original token is unchanged (tokens are immutable binaries); the new token carries the old caveats in order, followed by the new one.

- `CapabilityToken.inspect_token(token)` — decodes a token **without any key and without checking the signature**. Returns `{:ok, %{identifier: identifier, caveats: caveats}}` where `caveats` is the list of caveat binaries in the order they were attached, or `{:error, :malformed}` if the token cannot be decoded (including for non-binary input). This is a debugging/introspection helper — it makes no authenticity claim whatsoever.

- `CapabilityToken.authorize(token, root_key, context)` — the real check. `context` is a map describing the request being authorized. Returns `:ok` if the token's signature chain verifies under `root_key` **and** every caveat is satisfied by `context`. Otherwise returns `{:error, reason}` (see the section on check order and error values).

## Wire format

The decoded binary is built exactly as follows (all integers big-endian, unsigned), and is then passed through `Base.url_encode64/2` with `padding: false` so the token is URL-safe and contains no `+`, `/`, or `=`:

    <<1,                              # version byte, always 1
      id_size::16, identifier::binary-size(id_size),
      caveat_count::16,
      # caveat_count repetitions of:
      #   <<len::16, caveat::binary-size(len)>>
      signature::binary-32>>

Consequently, the signature is always the trailing 32 bytes of the decoded binary.

## Signature chain

The signature is an HMAC-SHA256 chain in which each caveat re-keys the MAC with the previous signature:

    sig_0 = :crypto.mac(:hmac, :sha256, root_key, identifier)
    sig_i = :crypto.mac(:hmac, :sha256, sig_{i-1}, caveat_i)

The token carries only the final signature `sig_n`. This is what makes attenuation keyless — a holder can extend the chain from the signature already in hand — while forgery stays impossible: the chain cannot be walked backwards to drop, reorder, or edit a caveat, since doing so requires the root key. `authorize/3` recomputes the whole chain from `root_key` and the token's own identifier + caveats and compares the result to the carried signature **in constant time** (no short-circuit on the first differing byte).

## Caveat language

A caveat is a binary of the form `"key = value"` — a key, then a space, an equals sign, and a space, then the value (the value may itself contain spaces or `=`; only the first `" = "` separates). Exactly three keys are recognized:

- `"expires_at = <integer>"` — satisfied iff `context[:now]` is an integer and `context[:now] < <integer>`. Strictly less: at exactly the expiry second the caveat is **not** satisfied. The value must parse as a complete integer (leading `-` allowed, trailing garbage not).
- `"action = <string>"` — satisfied iff `context[:action]` is exactly equal to `<string>` (binary equality).
- `"resource_prefix = <string>"` — satisfied iff `context[:resource]` is a binary that starts with `<string>`.

Everything else **fails closed**: an unrecognized key, a caveat with no `" = "` separator, a non-integer `expires_at` value, or a context that is missing the key a caveat needs — all count as *not satisfied*. An unknown caveat is never treated as vacuously true.

## Check order and error values inside `authorize/3`

Exactly this order applies:

1. base64 decode → structural parse (version byte, sizes, caveat count, exactly 32 trailing signature bytes). Any failure here, or a non-binary token / non-binary root key / non-map context, yields `{:error, :malformed}`.
2. signature chain verification → mismatch yields `{:error, :invalid_signature}`.
3. caveats, evaluated in attachment order → the **first** unsatisfied caveat yields `{:error, {:caveat_failed, caveat}}`, where `caveat` is that caveat's exact binary. Later caveats are not evaluated.

Signature verification always precedes caveat evaluation, so a token that is both expired and signed with the wrong key reports `:invalid_signature`, never `{:caveat_failed, _}`.

## Edge cases

- Empty caveats and caveats longer than 65_535 bytes are rejected by `attenuate/2` with `{:error, :malformed}`.
- Non-binary `token` or `caveat` arguments to `attenuate/2` yield `{:error, :malformed}`.
- Non-binary input to `inspect_token/1`, and any token that cannot be decoded, yield `{:error, :malformed}`.
- A token with zero caveats is valid; `mint/2` produces exactly that.
- Attenuation leaves the original token binary untouched, and the new token preserves the previous caveat order with the new caveat last.
- At exactly the `expires_at` second, the caveat is not satisfied (the comparison is strict).
- A missing `context` key, an unrecognized caveat key, a missing `" = "` separator, or an unparsable `expires_at` integer all count as not satisfied rather than satisfied.

## Implementation requirements

- `:crypto.mac/4` with SHA-256 for every link of the chain.
- `Base.url_encode64/2` / `Base.url_decode64/2` with `padding: false`.
- Constant-time signature comparison.
- No external dependencies — Elixir standard library and OTP only.
- No process state, no ETS, no files.
