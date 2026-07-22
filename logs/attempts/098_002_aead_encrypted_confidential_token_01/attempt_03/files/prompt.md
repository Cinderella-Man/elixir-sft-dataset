Write me an Elixir module called `SealedToken` that produces *encrypted*,
expiring tokens without any database or persistent state. Unlike a plain
signed token, the payload here must be **confidential** — an observer who
holds the token but not the key must not be able to read the payload at
all. Use authenticated encryption (AEAD) so that confidentiality and
integrity come from the same primitive.

I need these two functions in the public API:

- `SealedToken.seal(payload, key, ttl_seconds, opts \\ [])` where `payload`
  is any Elixir term, `key` is a 32-byte binary (an AES-256 key), and
  `ttl_seconds` is a positive integer. It must return a URL-safe binary
  token (no padding issues, safe to embed in URLs or headers) that
  encrypts the payload together with its issue timestamp and expiration
  timestamp. Each call must use a fresh random 12-byte nonce, so sealing
  the same payload twice yields two *different* tokens.

- `SealedToken.open(token, key, opts \\ [])` which decrypts and validates
  the token. Return `{:ok, payload}` if the token authenticates and has
  not expired. Return `{:error, :expired}` if the token authenticates but
  the current time is at or past the expiration. Return `{:error, :invalid}`
  if the structure is present but authentication fails — a wrong key,
  tampered bytes, or any input that has at least the minimum length but is
  not a genuine ciphertext produced with this key. Return
  `{:error, :malformed}` for anything that cannot even be structurally
  read: bad base64, a decoded length shorter than the 12-byte nonce plus
  the 16-byte tag (28 bytes), or non-binary input.

Both functions take an optional `opts` keyword. The only recognized key is
`:clock`, a zero-arity function returning a Unix epoch second. When
omitted, the current time is read from `System.os_time(:second)`. This is
purely a test seam for deterministic expiry testing — in production the
default applies.

The check order inside `open` is exactly: base64 decode → split off the
leading 12-byte nonce and 16-byte tag → AEAD decrypt-and-authenticate →
parse the plaintext (issue time, expiry time, payload bytes) → expiry
check → payload deserialization. Any failure before authentication yields
`:malformed`. An authentication failure yields `:invalid`. A post-decrypt
expiry failure yields `:expired`; a post-decrypt parse or deserialization
failure yields `:malformed`. Because the payload lives inside the
ciphertext, authentication necessarily happens before the expiry check —
so a token that is both expired and opened with the wrong key returns
`:invalid`, never `:expired`.

A token whose `expires_at` equals the current time is already expired (use
strict `<` on the validity check, not `<=`).

Because the payload is encrypted, the plaintext bytes of the payload must
not appear anywhere in the token: base64-decoding the token and searching
for a payload marker must find nothing.

Implementation requirements:

- Use `:crypto.crypto_one_time_aead/6,7` with the `:aes_256_gcm` cipher for
  both sealing and opening.
- Generate the 12-byte nonce with `:crypto.strong_rand_bytes/1`; the
  authentication tag is 16 bytes.
- Use `Base.url_encode64/2` with `padding: false` so the output is
  URL-safe without `=` characters.
- Deserialize the payload with `:erlang.binary_to_term/2` using the
  `[:safe]` option.
- Do not use any external dependencies — only the Elixir standard library
  and OTP.

Give me the complete module in a single file.