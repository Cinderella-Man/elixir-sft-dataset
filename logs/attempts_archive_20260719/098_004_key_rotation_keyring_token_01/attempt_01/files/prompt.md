Write me an Elixir module called `RotatingToken` that generates and validates
signed, expiring tokens against a **keyring** of multiple secrets, so keys can
be rotated without invalidating tokens still in flight. Each token records
*which* key signed it, and verification looks that key up in a caller-supplied
keyring. There is no database or persistent state.

A **keyring** is a map `%{key_id => secret}` where `key_id` is a binary key
identifier (a "kid") and `secret` is a binary signing key.

Public API:

- `RotatingToken.generate(payload, keyring, active_kid, ttl_seconds, opts \\ [])`
  where `payload` is any Elixir term, `keyring` is such a map, `active_kid` is
  the key id to sign with (it must be a key present in `keyring`), and
  `ttl_seconds` is a positive integer. It signs with `keyring[active_kid]`
  and returns a URL-safe binary token (no padding issues, safe to embed in
  URLs or headers) that encodes the key id, the payload, the issue timestamp,
  the expiration timestamp, and an HMAC-SHA256 signature over all of that
  data.

- `RotatingToken.verify(token, keyring, opts \\ [])` decodes the token, reads
  the embedded key id, looks it up in `keyring`, and validates. Return
  `{:ok, payload}` if the key id is known, the signature is valid, and the
  token has not expired. Otherwise return one of `{:error, :expired}`,
  `{:error, :invalid_signature}`, `{:error, :unknown_key}`, or
  `{:error, :malformed}` as described below.

The check order inside `verify` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header (key id, timestamps)
and payload → key-id lookup in the keyring → HMAC verification with the
looked-up key → expiry check → payload deserialization. Consequences:

- Any failure before the key-id lookup yields `:malformed` (bad base64, too
  short to contain a MAC, a header that doesn't match the remaining bytes,
  non-binary input, and so on).
- If the embedded key id is not a key in `keyring`, return `:unknown_key`.
  Because the lookup precedes both HMAC verification and the expiry check, a
  token whose key id has been dropped from the keyring returns `:unknown_key`
  even if its signature would be wrong and even if it is already expired. This
  is how you retire a key: remove its id from the keyring and every token
  signed with it becomes `:unknown_key`.
- If the key id is known but the HMAC computed with `keyring[key_id]` does not
  match, return `:invalid_signature`. Because the signature check precedes the
  expiry check, an expired token that also fails the signature returns
  `:invalid_signature`.
- A known-key, valid-signature, but expired token yields `:expired`. A token
  whose `expires_at` equals the current time is already expired (use strict
  `<` on the validity check, not `<=`).
- A post-HMAC deserialization failure yields `:malformed`.

Both `generate` and `verify` take an optional `opts` keyword. The only
recognized key is `:clock`, a zero-arity function returning a Unix epoch
second. When omitted, the current time is read from `System.os_time(:second)`.
This is purely a test seam for deterministic expiry testing.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false`.
- The key id must live inside the signed region along with the payload and
  timestamps, so an attacker cannot swap the key id without invalidating the
  signature. Include whatever length prefixes you need for framing (the key
  id is a variable-length binary) inside the signed region too.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using `[:safe]`.
- Do not use any external dependencies — only the Elixir standard library
  and OTP.

Give me the complete module in a single file.