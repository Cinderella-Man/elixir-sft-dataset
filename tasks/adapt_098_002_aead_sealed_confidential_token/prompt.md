# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

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

Write me an Elixir module called `SealedToken` that produces and opens
*encrypted*, expiring tokens without any database or persistent state.
Unlike a plain signed token, the payload here must be **confidential** —
an observer who does not hold the key must not be able to read it — and
tamper-evident at the same time. Use authenticated encryption (AES-256-GCM)
so that a single operation gives you both secrecy and integrity.

I need these two functions in the public API:

- `SealedToken.seal(payload, key, ttl_seconds, opts \\ [])` where
  `payload` is any Elixir term, `key` is a 32-byte binary encryption key,
  and `ttl_seconds` is a positive integer. It must return a URL-safe
  binary token (no padding issues, safe to embed in URLs or headers) that
  carries a fresh random 12-byte nonce, the issue timestamp, the
  expiration timestamp, the GCM authentication tag, and the encrypted
  payload. Because a fresh random nonce is chosen on every call, sealing
  the same payload twice yields two *different* tokens; both must open
  successfully.

- `SealedToken.open(token, key, opts \\ [])` which decodes, authenticates,
  decrypts, and validates the token. Return `{:ok, payload}` if the token
  authenticates and has not expired. Return `{:error, :expired}` if the
  token authenticates but the current time is at or past the expiration.
  Return `{:error, :invalid}` if the token parses structurally but fails
  authenticated decryption (wrong key, tampered ciphertext, tampered
  nonce, or tampered timestamps — the timestamps are part of the
  authenticated data, so they cannot be altered independently). Return
  `{:error, :malformed}` for anything that cannot be structurally decoded
  at all: bad base64, too short to contain a nonce + timestamps + tag,
  non-binary input, and so on.

Both functions take an optional `opts` keyword. The only recognized key
is `:clock`, a zero-arity function returning a Unix epoch second. When
omitted, the current time is read from `System.os_time(:second)`. This is
purely a test seam for deterministic expiry testing — in production the
default applies.

The check order inside `open` is exactly: base64 decode → structural
parse (peel off the 12-byte nonce, the two 64-bit timestamps, and the
16-byte tag) → authenticated decryption → expiry check → payload
deserialization. Any structural failure before authenticated decryption
yields `:malformed`. An authentication failure yields `:invalid`.
Authentication is therefore always checked *before* expiry, so a token
opened with the wrong key that also happens to be past its expiry returns
`:invalid`, never `:expired`. A post-decryption expiry failure yields
`:expired`. A post-decryption deserialization failure yields `:malformed`.
A token whose `expires_at` equals the current time is already expired (use
strict `<` on the validity check, not `<=`).

Implementation requirements:

- Use `:crypto.crypto_one_time_aead/6,7` with the `:aes_256_gcm` cipher.
- The two timestamps must be passed as the AAD (additional authenticated
  data) so they are covered by the tag without being encrypted.
- Use `Base.url_encode64/2` with `padding: false` so the output is
  URL-safe without `=` characters.
- Generate the nonce with `:crypto.strong_rand_bytes/1`.
- Deserialize the payload with `:erlang.binary_to_term/2` using the
  `[:safe]` option.
- Do not use any external dependencies — only the Elixir standard library
  and OTP.

Give me the complete module in a single file.
