Write me an Elixir module called `ScopedToken` that generates and validates
signed tokens that are **bound to a specific audience** and carry a **validity
window** with both a not-before time and an expiry — no database or persistent
state. A token issued for one audience must not verify when presented for a
different audience, and a token may be issued so that it only becomes valid at
some point in the future.

I need these two functions in the public API:

- `ScopedToken.generate(payload, secret, audience, ttl_seconds, opts \\ [])`
  where `payload` is any Elixir term, `secret` is a binary signing key,
  `audience` is a binary label the token is bound to (for example `"web"` or
  `"mobile"`), and `ttl_seconds` is a positive integer. It must return a
  URL-safe binary token (no padding issues, safe to embed in URLs or headers)
  that encodes the payload, the issue timestamp, a not-before timestamp, the
  expiration timestamp, the audience, and an HMAC-SHA256 signature over all of
  that data. The expiration is `issued_at + ttl_seconds`. The not-before
  timestamp is `issued_at + not_before`, where `not_before` comes from `opts`
  (see below) and defaults to `0`.

- `ScopedToken.verify(token, secret, expected_audience, opts \\ [])` which
  decodes and validates the token against `expected_audience`. Return
  `{:ok, payload}` if the signature is valid, the token's audience matches
  `expected_audience` exactly, and the current time falls within the validity
  window (at or after the not-before time and strictly before the expiry).
  Otherwise return one of:
  - `{:error, :invalid_signature}` if the token structure parses cleanly but the
    HMAC does not match.
  - `{:error, :audience_mismatch}` if the signature is valid but the token's
    audience does not exactly equal `expected_audience`.
  - `{:error, :not_yet_valid}` if the signature and audience are fine but the
    current time is before the not-before time.
  - `{:error, :expired}` if the signature and audience are fine and the token is
    within its not-before window but the current time is at or past the expiry.
  - `{:error, :malformed}` for anything that cannot be decoded at all: bad
    base64, too short to contain an HMAC, a header that doesn't match the
    remaining bytes, non-binary input, and so on.

The check order inside `verify` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse of the header (issue time, not-before
time, expiry time, audience, payload) → HMAC verification → audience match →
not-before check → expiry check → payload deserialization. Any failure before
HMAC verification is a structural problem and yields `:malformed`. An HMAC
mismatch yields `:invalid_signature`. A post-HMAC deserialization failure yields
`:malformed`.

Precedence matters and follows directly from that order:

- `:invalid_signature` takes precedence over `:audience_mismatch`, `:not_yet_valid`,
  and `:expired` — the signature is always checked first, so a token verified
  with the wrong secret returns `:invalid_signature` no matter what its audience
  or timestamps are.
- `:audience_mismatch` takes precedence over `:not_yet_valid` and `:expired`, so
  an expired token presented for the wrong audience returns `:audience_mismatch`.
- `:not_yet_valid` is checked before `:expired`.

Boundary rules:

- The token becomes valid at exactly its not-before time: the not-before check
  passes when the current time is greater than or equal to the not-before
  timestamp (use `>=`).
- A token whose `expires_at` equals the current time is already expired: the
  expiry check passes only when the current time is strictly less than the
  expiry (use `<`, not `<=`).
- With the default `not_before` of `0`, the not-before timestamp equals the
  issue time, so the token is immediately valid.

Both functions take an optional `opts` keyword. In `verify`, the only
recognized key is `:clock`, a zero-arity function returning a Unix epoch second.
In `generate`, two keys are recognized: `:clock` (same meaning) and
`:not_before`, a non-negative integer number of seconds after the issue time
before which the token is not valid (default `0`). When `:clock` is omitted, the
current time is read from `System.os_time(:second)`. The clock is purely a test
seam for deterministic testing — in production the default applies.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe
  without `=` characters.
- The signed region must cover all fields (payload bytes + issue time +
  not-before time + expiry time + the audience, plus any length prefixes you
  include for framing) so that none of them — including the audience — can be
  tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the `[:safe]`
  option.
- Do not use any external dependencies — only the Elixir standard library and
  OTP.

Give me the complete module in a single file.