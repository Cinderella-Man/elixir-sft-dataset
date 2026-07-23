# Design brief: `SingleUseToken`

## Problem

We need signed, expiring tokens that can be redeemed **at most once**. A purely
stateless token can be replayed indefinitely by anyone who captures it; we want
the opposite. The issuing server must remember which tokens have already been
consumed and reject any replay. Because redemption mutates shared state, all of
it has to run through a single serializing GenServer.

Deliverable: an Elixir GenServer module called `SingleUseToken` that issues and
redeems these tokens. Consumed-token bookkeeping is held in memory only — no
database.

## Constraints

- Use `:crypto.mac/4` with SHA-256 for signing.
- Generate the nonce with `:crypto.strong_rand_bytes/1`.
- Use `Base.url_encode64/2` with `padding: false` so the output is URL-safe
  without `=` characters.
- The signed region must cover all fields (the nonce, payload bytes, issue
  time, expiry time, plus any length prefix you include for framing) so that
  none of them can be tampered with independently.
- Compare MACs in constant time — don't short-circuit on the first differing
  byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the `[:safe]`
  option.
- Do not use any external dependencies — only the Elixir standard library and
  OTP.
- Ship the complete module in a single file.

## Required interface

1. **`SingleUseToken.start_link(opts)`** — `opts` is a keyword list. It
   recognizes:
   1. `:secret` (required) — a binary HMAC signing key used for every token
      this server issues and redeems.
   2. `:clock` (optional) — a zero-arity function returning a Unix epoch
      second. When omitted, the current time is read from
      `System.os_time(:second)`. This is purely a test seam for deterministic
      expiry testing.
   3. `:name` (optional) — a name to register the server under.

   It returns `{:ok, pid}`.

2. **`SingleUseToken.issue(server, payload, ttl_seconds)`** — `payload` is any
   Elixir term and `ttl_seconds` is a positive integer. It returns a URL-safe
   binary token (no padding issues, safe to embed in URLs or headers) that
   encodes a fresh unique nonce, the payload, the issue timestamp, the
   expiration timestamp, and an HMAC-SHA256 signature over all of that data.
   Every call produces a token with a distinct random nonce, so two tokens are
   always independent of each other.

3. **`SingleUseToken.redeem(server, token)`** — decodes, validates, and, on
   success, *consumes* the token. Results:
   1. `{:ok, payload}` the first time a valid, unexpired, not-yet-consumed
      token is redeemed; that redemption marks the token's nonce as consumed.
   2. `{:error, :replayed}` on any subsequent redemption of the same token
      (its nonce is already consumed).
   3. `{:error, :expired}` if the signature is valid and the token has not been
      consumed but the current time is at or past the expiration.
   4. `{:error, :invalid_signature}` if the token structure parses cleanly but
      the HMAC (computed with the server's secret) does not match.
   5. `{:error, :malformed}` for anything that cannot be decoded at all: bad
      base64, too short to contain an HMAC, a header that doesn't match the
      remaining bytes, non-binary token input, and so on.

4. **The check order inside `redeem`** is exactly: base64 decode → split off the
   trailing 32-byte MAC → structural parse of the header (nonce, issue time,
   expiry time) and payload → HMAC verification → replay check → expiry check →
   consume the nonce and deserialize the payload.

## Acceptance criteria

- Any failure before HMAC verification yields `:malformed`.
- HMAC mismatch yields `:invalid_signature`.
- The replay check happens *before* the expiry check, which means a token that
  has already been consumed returns `:replayed` forever — even after it would
  otherwise have expired.
- A token that is unexpired-but-consumed returns `:replayed`; a token that is
  expired-but-never-consumed returns `:expired`.
- A token whose `expires_at` equals the current time is already expired (use
  strict `<` on the validity check, not `<=`).
- The nonce is consumed only on the fully successful path — none of the failure
  results (`:malformed`, `:invalid_signature`, `:replayed`, `:expired`) consume
  anything.
