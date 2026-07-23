# Design Brief: `BoundedIdempotentPayments`

## Problem

We need an Elixir GenServer module called `BoundedIdempotentPayments` that simulates an idempotent payment processing system with in-memory storage. Unlike a conventional idempotency store that remembers keys for a fixed time window and sweeps expired ones, this store's idempotency layer must be **capacity-bounded with LRU eviction instead of TTL expiry**: it keeps at most a configured number of idempotency keys, and when a brand-new key would overflow that budget, the least-recently-used key is evicted first.

## Constraints

- There is no clock-based expiry and no periodic cleanup.
- Recency must be tracked deterministically with an internal monotonic access counter (a "tick"), NOT wall-clock time — every insert and every cache hit advances the tick and stamps the touched key.
- Payment records are never evicted — only idempotency keys are bounded.
- Use only the OTP standard library.
- Deliver the complete module in a single file.

## Required Interface

1. `BoundedIdempotentPayments.start_link(opts)` accepting:
   - `:max_keys` — a positive integer, the maximum number of idempotency keys retained; default 1000. Raise `ArgumentError` if it is not a positive integer.
   - `:clock` — a zero-arity ms clock used only for the `:created_at` timestamp; default `fn -> System.monotonic_time(:millisecond) end`.

2. `BoundedIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), `:recipient` (string). Semantics:
   1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
   2. If the key is present in the store, return the exact cached result and **refresh its recency** (mark it most-recently-used).
   3. If the key is absent (never seen or previously evicted), process the payment. If the store is already at `:max_keys`, evict the least-recently-used key first, then insert this key as most-recently-used. Return the result.
   4. If required fields are missing, return `{:error, :invalid_params}`; when a key was provided, cache that error result under the key too (it occupies a slot and participates in LRU just like a success).

   A successful `response` map contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).

3. `BoundedIdempotentPayments.get_payments(server)` returns all payment records (oldest first).

4. `BoundedIdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.

5. `BoundedIdempotentPayments.keys_by_recency(server)` returns the currently retained idempotency keys ordered least-recently-used first (for inspection/testing).

## Acceptance Criteria

- `start_link/1` honors `:max_keys` (default 1000) and raises `ArgumentError` when `:max_keys` is not a positive integer; `:clock` defaults to `fn -> System.monotonic_time(:millisecond) end` and is used only for the `:created_at` timestamp.
- A `nil` idempotency key always creates a new payment record and returns `{:ok, response}`.
- A present key returns the exact cached result and marks that key most-recently-used.
- An absent key processes the payment, and when the store is already at `:max_keys` it evicts the least-recently-used key before inserting the new key as most-recently-used.
- Missing required fields yield `{:error, :invalid_params}`, and when a key was provided that error result is cached under the key, occupying a slot and participating in LRU like a success.
- Recency is driven by the internal monotonic tick (advanced and stamped on every insert and every cache hit), never wall-clock time.
- A successful `response` contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).
- `get_payments/1` returns records oldest first; `get_payment/2` returns `{:ok, payment}` or `{:error, :not_found}`; `keys_by_recency/1` returns retained keys least-recently-used first.
- Payment records are never evicted — only idempotency keys are bounded — and the module uses only the OTP standard library, delivered as one complete file.
