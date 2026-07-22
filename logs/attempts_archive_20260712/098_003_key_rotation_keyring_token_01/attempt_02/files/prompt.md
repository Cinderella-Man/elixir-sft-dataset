Write me an Elixir module called `KeyringToken` that generates and validates
signed, expiring tokens using a *keyring* of named signing keys, so keys can be
rotated without invalidating in-flight tokens. There is no database or
persistent state — every token is self-contained.

I need these two functions in the public API:

- `KeyringToken.generate(payload, keyring, key_id, ttl_seconds, opts \\ [])`
  where `payload` is any Elixir term, `keyring` is a map of
  `%{key_id => secret_binary}` (each key id is a binary and each secret is a
  binary signing key), `key_id` is the binary naming which secret to sign
  with, and `ttl_seconds` is a positive integer. It must return a URL-safe
  binary token (no padding issues, safe to embed in URLs or headers) that
  encodes the payload, the `key_id`, the issue timestamp, the expiration
  timestamp, and an HMAC-SHA256 signature over all of that data (including the
  `key_id`). If `key_id` is not present in `keyring`, `generate/5` must raise
  `ArgumentError`.

- `KeyringToken.verify(token, keyring, opts \\ [])` which decodes and validates
  the token. It reads the `key_id` embedded in the token, looks that id up in
  the supplied `keyring`, and uses the corresponding secret to verify the
  signature. Return `{:ok, payload}` if the embedded key id is known, the
  signature is valid, and the token has not expired. Return
  `{:error, :unknown_key}` if the token parses cleanly but its embedded key id
  is not present in `keyring`. Return `{:error, :invalid_signature}` if the
  token structure parses cleanly and the key id is known but the HMAC does not
  match. Return `{:error, :expired}` if the key is known and the signature is
  valid but the current time is at or past the expiration. Return
  `{:error, :malformed}` for anything that cannot be decoded at all: bad
  base64, too short to contain an HMAC, a header that doesn't match the
  remaining bytes, non-binary token input, a `keyring` that is not a map, and
  so on.

Both functions take an optional `opts` keyword. The only recognized key is
`:clock`, a zero-arity function returning a Unix epoch second. When omitted,
the current time is read from `System.os_time(:second)`. This is purely a test
seam for deterministic expiry testing — in production the default applies.

The check order inside `verify` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header (key id, issue time,
expiry time) and payload → keyring lookup of the embedded key id → HMAC
verification → expiry check → payload deserialization. Any failure before the
keyring lookup yields `:malformed`. A key id that is not in the keyring yields
`:unknown_key` — this is decided *before* HMAC verification and *before* the
expiry check, so an unknown-key token that also happens to be expired still
returns `:unknown_key`. An HMAC mismatch (for a known key) yields
`:invalid_signature`, and this is decided *before* the expiry check, so a
wrong-secret token that is also expired returns `:invalid_signature`, never
`:expired`. A post-HMAC expiry failure yields `:expired`. A token whose
`expires_at` equals the current time is already expired (use strict `<` on the
validity check, not `<=`). A post-HMAC deserialization failure yields
`:malformed`.

Key rotation works like this: during a rotation window the caller keeps both
the old and the new secret in the keyring, so tokens signed with either key
still verify. Once the old key is dropped from the keyring, any token that was
signed with it verifies to `{:error, :unknown_key}`.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe
  without `=` characters.
- The signed region must cover all fields (the key id, payload bytes, issue
  time, expiry time, plus any length prefixes you include for framing) so that
  none of them — including the key id — can be tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the `[:safe]`
  option.
- Do not use any external dependencies — only the Elixir standard library and
  OTP.

Give me the complete module in a single file.