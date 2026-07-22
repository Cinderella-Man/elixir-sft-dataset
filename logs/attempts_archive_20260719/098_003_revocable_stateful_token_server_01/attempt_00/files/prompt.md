Write me an Elixir module called `RevocableToken` that issues and validates
signed, expiring tokens — but unlike a purely stateless token, this one
supports **revocation**. The module is a `GenServer` that owns the signing
secret and maintains an in-memory set of revoked tokens. Once a token is
revoked it must fail validation on that server even though its signature is
still cryptographically valid and it has not yet expired.

Public API (all functions take a server pid or name as the first argument):

- `RevocableToken.start_link(opts)` starts the server. `opts` is a keyword
  list. The `:secret` key (a binary signing key) is required. The optional
  `:clock` key is a zero-arity function returning a Unix epoch second; when
  omitted the server reads `System.os_time(:second)`. This is a test seam.
  Returns `{:ok, pid}`.

- `RevocableToken.issue(server, payload, ttl_seconds)` where `payload` is any
  Elixir term and `ttl_seconds` is a positive integer. Returns `{:ok, token}`
  where `token` is a URL-safe binary (no padding issues, safe to embed in
  URLs or headers) that encodes the payload, the issue timestamp, the
  expiration timestamp, a server-generated unique id, and an HMAC-SHA256
  signature over all of that data. Because each token carries a fresh random
  id, issuing the same payload twice produces two *different* tokens.

- `RevocableToken.verify(server, token)` decodes and validates the token
  against that server. Return `{:ok, payload}` if the signature is valid, the
  token is not revoked, and it has not expired. Return `{:error, :expired}`,
  `{:error, :invalid_signature}`, `{:error, :revoked}`, or
  `{:error, :malformed}` as described below. `verify` is read-only: verifying
  a token any number of times does not change its status.

- `RevocableToken.revoke(server, token)` marks `token` as revoked on that
  server and returns `:ok`. Revocation is per-token: revoking one token does
  not affect any other token. Revocation is per-server: revoking a token on
  one server does not revoke it on another.

The check order inside `verify` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header and payload → HMAC
verification → revocation check → expiry check → payload deserialization.
Consequences of this order:

- Any failure before HMAC verification yields `:malformed` (bad base64, too
  short to contain a MAC, a header that doesn't match the remaining bytes,
  non-binary input, and so on).
- An HMAC mismatch yields `:invalid_signature`. Because the signature is
  checked before the revocation status, a token whose signature does not
  verify against this server's secret returns `:invalid_signature` even if it
  has been revoked on this server.
- A revoked token with a valid signature yields `:revoked`. Because the
  revocation check runs before the expiry check, a token that is both revoked
  and past its expiry returns `:revoked`.
- A valid, non-revoked, but expired token yields `:expired`. A token whose
  `expires_at` equals the current time is already expired (use strict `<` on
  the validity check, not `<=`).
- A post-HMAC deserialization failure yields `:malformed`.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false`.
- The signed region must cover all fields (unique id + issue time + expiry
  time + payload, plus any length prefix you include for framing) so that
  none of them can be tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Generate the per-token unique id with `:crypto.strong_rand_bytes/1`.
- Deserialize the payload with `:erlang.binary_to_term/2` using `[:safe]`.
- Do not use any external dependencies — only the Elixir standard library
  and OTP.

Give me the complete module in a single file.