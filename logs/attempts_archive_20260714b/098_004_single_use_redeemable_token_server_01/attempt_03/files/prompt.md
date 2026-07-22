Write me an Elixir module called `SingleUseToken`, backed by a GenServer,
that issues signed, expiring, **single-use** tokens and redeems them
exactly once. The signing part is stateless HMAC (as with an ordinary
signed token), but the server additionally keeps an in-memory ledger of
which tokens have already been redeemed, so a replayed token is rejected.

I need this public API:

- `SingleUseToken.start_link(opts)` starts a server. `opts` is a keyword
  list that must contain `:secret` (a binary HMAC key) and may contain
  `:clock` (a zero-arity function returning a Unix epoch second) and
  `:name`. Returns `{:ok, pid}`. When `:clock` is omitted the server reads
  time from `System.os_time(:second)`. The `:clock` option is purely a
  test seam for deterministic expiry testing.

- `SingleUseToken.issue(server, payload, ttl_seconds)` where `payload` is
  any Elixir term and `ttl_seconds` is a positive integer. Returns
  `{:ok, token}` where `token` is a URL-safe binary (no padding issues)
  encoding a unique per-token id, the issue timestamp, the expiration
  timestamp, the payload, and an HMAC-SHA256 signature over all of that.
  Every call produces a token with a fresh unique id, so issuing the same
  payload twice yields two different tokens.

- `SingleUseToken.redeem(server, token)` which validates and consumes the
  token. Return `{:ok, payload}` on the first successful redemption of a
  token. Return `{:error, :already_redeemed}` if that exact token has
  already been successfully redeemed on this server. Return
  `{:error, :expired}` if the signature is valid but the current time is at
  or past the expiration. Return `{:error, :invalid_signature}` if the
  token structure parses cleanly but the HMAC does not match this server's
  secret. Return `{:error, :malformed}` for anything that cannot be decoded
  at all: bad base64, too short to contain a signature, a header that
  doesn't match the remaining bytes, non-binary input, and so on.

The check order inside `redeem` is exactly: base64 decode → split off the
trailing 32-byte MAC → structural parse (unique id, timestamps, payload) →
HMAC verification → expiry check → single-use check → payload
deserialization. Any structural failure before HMAC verification yields
`:malformed`. An HMAC mismatch yields `:invalid_signature`. A post-signature
expiry failure yields `:expired`. A post-expiry replay yields
`:already_redeemed`. A token whose `expires_at` equals the current time is
already expired (use strict `<`, not `<=`).

Important consequences of this order and of the ledger being in memory:

- The ledger is only updated on a *fully successful* redemption. A token
  that fails for any reason (`:malformed`, `:invalid_signature`,
  `:expired`) is **not** recorded and does not count as used.
- Signature is checked before expiry, and expiry before the single-use
  check. A token redeemed with the wrong server (wrong secret) returns
  `:invalid_signature` even if it is also expired or already redeemed
  elsewhere.
- The ledger is per-server: each server instance tracks only the tokens it
  has itself redeemed. Two separate servers do not share redemption state,
  so a token issued under a shared secret can be redeemed once on each
  server independently.

Implementation requirements:

- Use `:crypto.mac/4` with SHA-256 for signing, and `:crypto.strong_rand_bytes/1`
  for the per-token unique id.
- The signed region must cover the unique id, both timestamps, and the
  payload (plus any length prefixes) so none can be tampered with
  independently.
- Use `Base.url_encode64/2` with `padding: false`.
- Compare MACs in constant time — don't short-circuit on the first
  differing byte.
- Deserialize the payload with `:erlang.binary_to_term/2` using the
  `[:safe]` option.
- Redemption must be serialized through the GenServer so concurrent
  redemptions of the same token cannot both succeed.
- Do not use any external dependencies — only the Elixir standard library
  and OTP.

Give me the complete module in a single file.