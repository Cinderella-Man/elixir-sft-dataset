Write me an Elixir module called `RevocableToken` that generates and validates
signed, expiring tokens — but unlike a purely stateless design, it also supports
**explicit revocation** before a token's natural expiry, tracked by a small
GenServer.

The signing/verification core is the same idea as a stateless HMAC token: each
token embeds its payload, issue timestamp, expiration timestamp, and an
HMAC-SHA256 signature over all of that. On top of that, every token carries a
unique, unguessable token id (a "jti") of 16 random bytes, which is included in
the signed region. Revocation works by remembering revoked jtis in a supervised
GenServer.

Public API:

- `RevocableToken.start_link(opts \\ [])` — starts the revocation server. Accepts
  a `:name` option (any registered name); when given, the server registers under
  it. Returns `{:ok, pid}`.

- `RevocableToken.generate(payload, secret, ttl_seconds, opts \\ [])` — stateless;
  does not touch the server. `payload` is any term, `secret` a binary key,
  `ttl_seconds` a positive integer. Returns a URL-safe binary token (via
  `Base.url_encode64/2` with `padding: false`) that encodes payload, issue time,
  expiry time, a fresh random 16-byte jti, and an HMAC-SHA256 signature over all
  of that. Use `:crypto.strong_rand_bytes/1` for the jti.

- `RevocableToken.verify(server, token, secret, opts \\ [])` — decodes and
  validates. Returns `{:ok, payload}` when the signature is valid, the token is
  not expired, and the token's jti has not been revoked on `server`. Returns
  `{:error, :invalid_signature}` when the structure parses but the HMAC does not
  match; `{:error, :expired}` when the signature is valid but the current time is
  at or past the expiration; `{:error, :revoked}` when the signature is valid and
  the token is unexpired but its jti has been revoked; `{:error, :malformed}` for
  anything that cannot be decoded (bad base64, too short to contain the HMAC, a
  header that doesn't match the remaining bytes, non-binary input, post-HMAC
  deserialization failure).

- `RevocableToken.revoke(server, token)` — marks `token`'s jti as revoked on
  `server`. It parses the token structurally to extract the jti (it does NOT
  require the secret and does NOT verify the HMAC). Returns `:ok` on success, or
  `{:error, :malformed}` if the token can't be parsed enough to extract a jti.

The exact check order inside `verify` is: base64 decode → split off the trailing
32-byte MAC → structural parse of header + jti + payload → HMAC verification →
expiry check → revocation check → payload deserialization. Any failure before
HMAC verification yields `:malformed`. HMAC mismatch yields `:invalid_signature`.
So a wrong-secret token that is also revoked returns `:invalid_signature`, and a
revoked token that is also expired returns `:expired` (expiry is checked before
revocation). A token whose `expires_at` equals the current time is already
expired (strict `<` on the validity check).

Both `generate` and `verify` take an optional `:clock` in `opts`, a zero-arity
function returning a Unix epoch second; when omitted, `System.os_time(:second)`
is used. This is a test seam for deterministic expiry.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Compare MACs in constant time (no early exit on first differing byte).
- The signed region must cover payload bytes, issue time, expiry time, and the
  jti, plus any length prefix you use for framing.
- Deserialize the payload with `:erlang.binary_to_term/2` using `[:safe]`.
- No external dependencies — only the Elixir standard library and OTP.

Give me the complete module in a single file.