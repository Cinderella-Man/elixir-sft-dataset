Write me an Elixir module called `RotatingToken` that generates and validates
signed, expiring tokens against a **keyring** of multiple secrets, so that keys
can be rotated over time without invalidating tokens that were signed with an
older key. There is no database or persistent state — everything needed to
verify a token travels inside the token itself, except the secrets, which the
caller supplies as a keyring.

I need these two functions in the public API:

- `RotatingToken.generate(payload, keyring, active_key_id, ttl_seconds, opts \\ [])`
  where `payload` is any Elixir term, `keyring` is a map of `key_id => secret`
  (each `key_id` is a binary label and each `secret` is a binary signing key),
  `active_key_id` is the binary key id (present in `keyring`) that this token
  should be signed with, and `ttl_seconds` is a positive integer. It must return
  a URL-safe binary token (no padding issues, safe to embed in URLs or headers)
  that encodes the payload, the issue timestamp, the expiration timestamp, the
  key id used, and an HMAC-SHA256 signature over all of that data. The token is
  signed using the secret that `active_key_id` maps to in `keyring`.

- `RotatingToken.verify(token, keyring, opts \\ [])` which decodes and validates
  the token. It reads the key id embedded in the token, looks that key id up in
  `keyring`, and uses the corresponding secret to check the signature. Return
  `{:ok, payload}` if the key id is known, the signature is valid, and the token
  has not expired. Return `{:error, :unknown_key}` if the token parses cleanly
  but its embedded key id is not a key in `keyring`. Return
  `{:error, :invalid_signature}` if the key id is known but the HMAC does not
  match. Return `{:error, :expired}` if the signature is valid but the current
  time is at or past the expiration. Return `{:error, :malformed}` for anything
  that cannot be decoded at all: bad base64, too short to contain an HMAC, a
  header that doesn't match the remaining bytes, non-binary or non-map input,
  and so on.

The check order inside `verify` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header (issue time, expiry time,
key id, payload) → key lookup in the keyring → HMAC verification → expiry check
→ payload deserialization. Any failure before the key lookup is a structural
problem and yields `:malformed`. A key id that is absent from the keyring yields
`:unknown_key`. An HMAC mismatch yields `:invalid_signature`. A post-HMAC expiry
failure yields `:expired`. A post-HMAC deserialization failure yields
`:malformed`.

Precedence matters and follows directly from that order:

- `:unknown_key` takes precedence over `:invalid_signature` and over `:expired`
  (the key must be found before the signature or expiry can even be checked), so
  an expired token whose key id is not in the keyring returns `:unknown_key`.
- `:invalid_signature` takes precedence over `:expired`, so a token whose key id
  is known but whose secret is wrong returns `:invalid_signature` even if the
  token is also past its expiry.

Because the key id is one of the fields covered by the MAC, and because
verification selects the secret from the embedded key id, two tokens signed with
different key ids in the same keyring both verify successfully as long as both
key ids are present — this is exactly what makes key rotation work.

A token whose `expires_at` equals the current time is already expired (use
strict `<` on the validity check, not `<=`).

Both functions take an optional `opts` keyword. The only recognized key is
`:clock`, a zero-arity function returning a Unix epoch second. When omitted, the
current time is read from `System.os_time(:second)`. This is purely a test seam
for deterministic expiry testing — in production the default applies.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe
  without `=` characters.
- The signed region must cover all fields (payload bytes + issue time + expiry
  time + the key id, plus any length prefixes you include for framing) so that
  none of them — including the key id — can be tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the `[:safe]`
  option.
- Do not use any external dependencies — only the Elixir standard library and
  OTP.

Give me the complete module in a single file.