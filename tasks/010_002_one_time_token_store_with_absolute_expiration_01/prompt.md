# OneTimeTokenStore — Specification

## Overview

This document specifies an Elixir GenServer module named `OneTimeTokenStore` that manages single-use tokens (for example, password reset tokens or invite codes) with absolute expiration.

Each token must carry an independent absolute deadline. Unlike a session store, accessing a token does NOT extend its lifetime. `verify` is a read-only check; only `redeem` and `revoke` remove tokens.

The complete module is to be delivered in a single file. It must rely on only the OTP standard library, with no external dependencies.

## API

The public API is required to expose the following functions:

- `OneTimeTokenStore.start_link(opts)` starts the process. It should accept a `:clock` option, which is a zero-arity function returning the current time in milliseconds. If not provided, it defaults to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:default_ttl_ms` option for the default token lifetime (default 3600000, i.e. 1 hour).

- `OneTimeTokenStore.mint(server, payload, opts \\ [])` creates a new token containing the given payload. It accepts an optional `:ttl_ms` in opts to override the default TTL. It returns `{:ok, token_id}` where token_id is a unique string. The token's expiration is absolute — computed as `now + ttl_ms` at creation time and never extended.

- `OneTimeTokenStore.verify(server, token_id)` checks whether a token exists and has not expired, WITHOUT consuming it. It returns `{:ok, payload}` if the token is valid, or `{:error, :not_found}` if it doesn't exist, has been consumed, or has expired.

- `OneTimeTokenStore.redeem(server, token_id)` consumes a valid token, returning its payload and permanently removing it. It returns `{:ok, payload}` on success, or `{:error, :not_found}` if the token doesn't exist, was already redeemed, or has expired. A redeemed token can never be used again.

- `OneTimeTokenStore.revoke(server, token_id)` invalidates a token without redeeming it. It returns `:ok` regardless of whether the token existed.

- `OneTimeTokenStore.active_count(server)` returns the number of tokens that are still valid (not expired, not redeemed, not revoked). This must account for lazily expired tokens.

Token IDs are to be generated using `:crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)`.

## Cleanup and expiration

Expired tokens should be lazily cleaned up on access. In addition, a periodic sweep is required so the GenServer doesn't leak memory. The implementation runs a periodic cleanup using `Process.send_after` every 60 seconds (configurable via the `:cleanup_interval_ms` option) that removes any tokens whose absolute deadline has passed.

## Edge cases — additional interface contract

- The `:cleanup_interval_ms` option may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

- Sending the server process a bare `:cleanup` message performs one cleanup pass immediately — the same work the periodic timer performs.
