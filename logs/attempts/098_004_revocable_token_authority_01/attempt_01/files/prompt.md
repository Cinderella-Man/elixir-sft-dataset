Write me an Elixir module called `TokenAuthority`, implemented as a `GenServer`,
that issues and validates signed, expiring tokens **and supports revocation**.
The base HMAC-token design is stateless and can never take a token back; this
one keeps a small amount of in-process state (a set of revoked token ids) so an
operator can invalidate an individual outstanding token before it expires.

Each issued token carries a unique **token id** (a "jti"). The authority holds
the signing secret and the set of revoked jtis in its GenServer state. A token
is accepted only if it is well-formed, correctly signed by this authority's
secret, not expired, and its jti has not been revoked.

Public API:

- `TokenAuthority.start_link(opts)` — `opts` is a keyword list. It must accept
  `:secret` (a required binary signing key) and an optional `:clock` (a
  zero-arity function returning a Unix epoch second; when omitted the authority
  reads `System.os_time(:second)`, which is a test seam). It may also accept a
  `:name` for registration. Returns `{:ok, pid}`.

- `TokenAuthority.issue(server, payload, ttl_seconds)` where `payload` is any
  Elixir term and `ttl_seconds` is a positive integer. Returns
  `{:ok, token, jti}` where `token` is a URL-safe binary token (no padding
  issues, safe to embed in URLs or headers) encoding the jti, the payload, the
  issue timestamp, the expiration timestamp, and an HMAC-SHA256 signature over
  all of that data, and `jti` is the opaque binary token id you pass to
  `revoke/2` if you later want to invalidate this specific token.

- `TokenAuthority.verify(server, token)` which decodes and validates the token.
  Return `{:ok, payload}` if the token is well-formed, correctly signed by this
  authority's secret, not expired, and not revoked. Otherwise return one of the
  errors below.

- `TokenAuthority.revoke(server, jti)` which marks `jti` as revoked and returns
  `:ok`. Revocation is idempotent and it is fine to revoke a jti that was never
  issued (it simply joins the revoked set). Once a jti is revoked, every token
  carrying that jti fails verification with `{:error, :revoked}`.

Error semantics for `verify`:

- `{:error, :malformed}` — anything that cannot be decoded at all: bad base64,
  too short to contain an HMAC, a header (jti length prefix, timestamps,
  payload length) that doesn't match the remaining bytes, non-binary input,
  and so on.
- `{:error, :invalid_signature}` — the token structure parses cleanly but the
  HMAC does not match this authority's secret.
- `{:error, :expired}` — the signature is valid but the current time is at or
  past the expiration.
- `{:error, :revoked}` — the signature is valid and the token is not expired,
  but its jti is in the revoked set.

The check order inside `verify` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header, jti, and payload → HMAC
verification → expiry check → revocation check → payload deserialization. Any
failure before HMAC verification yields `:malformed`. An HMAC mismatch yields
`:invalid_signature`. A post-HMAC expiry failure yields `:expired`. A token that
is validly signed and unexpired but revoked yields `:revoked`. A post-HMAC
deserialization failure yields `:malformed`. A token whose `expires_at` equals
the current time is already expired (use strict `<` on the validity check, not
`<=`). Because expiry is checked before revocation, a token that is both expired
and revoked returns `:expired`.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe
  without `=` characters.
- The signed region must cover all fields (the jti bytes and their length
  prefix, the payload bytes, the issue time, and the expiry time, plus any
  length prefix you include for framing) so that none of them can be tampered
  with independently.
- Generate each jti from cryptographically strong randomness so distinct tokens
  get distinct ids; revoking one token's jti must not affect any other token.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the `[:safe]`
  option.
- Do not use any external dependencies — only the Elixir standard library and
  OTP.

Give me the complete module in a single file.