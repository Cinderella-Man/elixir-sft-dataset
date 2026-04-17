Write me an Elixir module called `SecureToken` that generates and validates
signed, expiring tokens without any database or persistent state.

I need these two functions in the public API:

- `SecureToken.generate(payload, secret, ttl_seconds, opts \\ [])` where
  `payload` is any Elixir term, `secret` is a binary signing key, and
  `ttl_seconds` is a positive integer. It must return a URL-safe binary
  token (no padding issues, safe to embed in URLs or headers) that
  encodes the payload, the issue timestamp, the expiration timestamp,
  and an HMAC-SHA256 signature over all of that data.

- `SecureToken.verify(token, secret, opts \\ [])` which decodes and
  validates the token. Return `{:ok, payload}` if the signature is valid
  and the token has not expired. Return `{:error, :expired}` if the
  signature is valid but the current time is at or past the expiration.
  Return `{:error, :invalid_signature}` if the token structure parses
  cleanly but the HMAC does not match. Return `{:error, :malformed}` for
  anything that cannot be decoded at all: bad base64, too short to
  contain an HMAC, a header that doesn't match the remaining bytes,
  non-binary input, and so on.

Both functions take an optional `opts` keyword. The only recognized key
is `:clock`, a zero-arity function returning a Unix epoch second. When
omitted, the current time is read from `System.os_time(:second)`. This
is purely a test seam for deterministic expiry testing — in production
the default applies.

The check order inside `verify` is exactly: base64 decode → split off
the trailing 32-byte MAC → structural parse of the header and payload
→ HMAC verification → expiry check → payload deserialization. Any
failure before HMAC verification yields `:malformed`. HMAC mismatch
yields `:invalid_signature`. A post-HMAC expiry failure yields
`:expired`. A post-HMAC deserialization failure yields `:malformed`.
A token whose `expires_at` equals the current time is already expired
(use strict `<` on the validity check, not `<=`).

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false` so the output is
  URL-safe without `=` characters.
- The signed region must cover all fields (payload bytes + issue time
  + expiry time, plus any length prefix you include for framing) so
  that none of them can be tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first
  differing byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the
  `[:safe]` option.
- Do not use any external dependencies — only the Elixir standard
  library and OTP.

Give me the complete module in a single file.