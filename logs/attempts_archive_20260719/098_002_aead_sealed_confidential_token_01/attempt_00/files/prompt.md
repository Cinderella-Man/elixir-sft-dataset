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