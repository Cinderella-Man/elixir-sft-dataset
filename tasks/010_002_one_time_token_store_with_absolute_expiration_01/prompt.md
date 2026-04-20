Write me an Elixir GenServer module called `OneTimeTokenStore` that manages single-use tokens (e.g., password reset tokens, invite codes) with absolute expiration.

I need these functions in the public API:

- `OneTimeTokenStore.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:default_ttl_ms` option for the default token lifetime (default 3600000, i.e. 1 hour).

- `OneTimeTokenStore.mint(server, payload, opts \\ [])` which creates a new token containing the given payload. Accept an optional `:ttl_ms` in opts to override the default TTL. Return `{:ok, token_id}` where token_id is a unique string. The token's expiration is absolute — computed as `now + ttl_ms` at creation time and never extended.

- `OneTimeTokenStore.verify(server, token_id)` which checks whether a token exists and has not expired, WITHOUT consuming it. Return `{:ok, payload}` if the token is valid, or `{:error, :not_found}` if it doesn't exist, has been consumed, or has expired.

- `OneTimeTokenStore.redeem(server, token_id)` which consumes a valid token, returning its payload and permanently removing it. Return `{:ok, payload}` on success, or `{:error, :not_found}` if the token doesn't exist, was already redeemed, or has expired. A redeemed token can never be used again.

- `OneTimeTokenStore.revoke(server, token_id)` which invalidates a token without redeeming it. Return `:ok` regardless of whether the token existed.

- `OneTimeTokenStore.active_count(server)` which returns the number of tokens that are still valid (not expired, not redeemed, not revoked). This must account for lazily expired tokens.

Each token must have an independent absolute deadline — unlike a session store, accessing a token does NOT extend its lifetime. `verify` is a read-only check; only `redeem` and `revoke` remove tokens.

Expired tokens should be lazily cleaned up on access, but you also need a periodic sweep so the GenServer doesn't leak memory. Run a periodic cleanup using `Process.send_after` every 60 seconds (configurable via `:cleanup_interval_ms` option) that removes any tokens whose absolute deadline has passed.

Token IDs should be generated using `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.