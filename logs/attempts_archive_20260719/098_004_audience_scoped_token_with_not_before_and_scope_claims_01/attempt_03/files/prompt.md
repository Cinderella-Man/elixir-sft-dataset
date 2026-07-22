Write me an Elixir module called `ScopedToken` that generates and validates
signed, expiring HMAC-SHA256 tokens carrying **richer claims**: an optional
audience binding, a not-before activation time, and a set of granted scopes.
Verification can require an expected audience and a set of required scopes, and
respects a not-before window — all in addition to signature and expiry checks.

Public API:

- `ScopedToken.generate(payload, secret, ttl_seconds, opts \\ [])` where
  `payload` is any Elixir term, `secret` is a binary key, and `ttl_seconds` is a
  positive integer. Recognized `opts`:
    * `:audience` — a binary audience the token is bound to (default `nil`).
    * `:scopes` — a list of binary scopes granted by the token (default `[]`).
    * `:not_before` — a non-negative integer number of seconds after the issue
      time before which the token is not yet valid (default `0`).
    * `:clock` — a zero-arity function returning a Unix epoch second (test seam).
  It returns a URL-safe binary token (via `Base.url_encode64/2` with
  `padding: false`) encoding the payload, issue time, not-before time, expiry
  time, and the claims (audience + scopes), with an HMAC-SHA256 signature over all
  of that data.

- `ScopedToken.verify(token, secret, opts \\ [])`. Recognized `opts`:
    * `:audience` — the expected audience. When given (non-nil), the token's bound
      audience must equal it. When omitted, audience is not checked.
    * `:scopes` — a list of required scopes; every one must be present in the
      token's granted scopes. Defaults to `[]` (no scope requirement).
    * `:clock` — as above.
  Return `{:ok, payload}` if all checks pass. Otherwise:
    * `{:error, :invalid_signature}` — structure parses but the HMAC mismatches.
    * `{:error, :not_yet_valid}` — signature valid but current time is before the
      not-before time.
    * `{:error, :expired}` — signature valid, past the not-before time, but at or
      past expiration.
    * `{:error, :audience_mismatch}` — signature valid and within the time window
      but the expected audience does not match the token's audience.
    * `{:error, :insufficient_scope}` — signature valid, in window, audience OK,
      but a required scope is missing.
    * `{:error, :malformed}` — bad base64, too short for the HMAC, a header that
      doesn't match the remaining bytes, non-binary input, or a post-HMAC
      deserialization failure of the claims/payload.

The exact check order inside `verify` is: base64 decode → split off the trailing
32-byte MAC → structural parse → HMAC verification → not-before check → expiry
check → claims deserialization → audience check → scope check → payload
deserialization. Anything failing before the HMAC yields `:malformed`; the HMAC
governs `:invalid_signature`; then the ordered claim checks apply. A token whose
`not_before` equals the current time is already active (use `>=` on the
activation check); a token whose `expires_at` equals the current time is already
expired (strict `<` on the validity check).

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- The signed region must cover the payload, all three timestamps, and the claims
  (audience + scopes), plus any length prefixes used for framing.
- Compare MACs in constant time (no early exit on first differing byte).
- Deserialize the claims and payload with `:erlang.binary_to_term/2` using
  `[:safe]`.
- No external dependencies — only the Elixir standard library and OTP.

Give me the complete module in a single file.