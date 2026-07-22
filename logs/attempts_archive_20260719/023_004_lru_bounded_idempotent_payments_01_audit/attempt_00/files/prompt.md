Write me an Elixir GenServer module called `BoundedIdempotentPayments` that simulates an idempotent payment processing system with in-memory storage where the idempotency store is **capacity-bounded with LRU eviction instead of TTL expiry**. Rather than remembering keys for a fixed time window and sweeping expired ones, the store keeps at most a configured number of idempotency keys; when a brand-new key would overflow that budget, the least-recently-used key is evicted first. There is no clock-based expiry and no periodic cleanup.

Public API:

- `BoundedIdempotentPayments.start_link(opts)` accepting `:max_keys` (a positive integer, the maximum number of idempotency keys retained; default 1000 — raise `ArgumentError` if it is not a positive integer) and `:clock` (zero-arity ms clock used only for the `:created_at` timestamp, default `fn -> System.monotonic_time(:millisecond) end`).

- `BoundedIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), `:recipient` (string). Semantics:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If the key is present in the store, return the exact cached result and **refresh its recency** (mark it most-recently-used).
  3. If the key is absent (never seen or previously evicted), process the payment. If the store is already at `:max_keys`, evict the least-recently-used key first, then insert this key as most-recently-used. Return the result.
  4. If required fields are missing, return `{:error, :invalid_params}`; when a key was provided, cache that error result under the key too (it occupies a slot and participates in LRU just like a success).

  Recency must be tracked deterministically with an internal monotonic access counter (a "tick"), NOT wall-clock time — every insert and every cache hit advances the tick and stamps the touched key. A successful `response` map contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).

- `BoundedIdempotentPayments.get_payments(server)` returns all payment records (oldest first).
- `BoundedIdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.
- `BoundedIdempotentPayments.keys_by_recency(server)` returns the currently retained idempotency keys ordered least-recently-used first (for inspection/testing).

Payment records are never evicted — only idempotency keys are bounded. Use only the OTP standard library. Give me the complete module in a single file.