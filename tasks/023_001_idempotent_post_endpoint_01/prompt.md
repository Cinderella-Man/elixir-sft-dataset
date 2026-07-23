# `IdempotentPayments` — idempotent in-memory payment GenServer

Implement an Elixir GenServer module `IdempotentPayments` simulating an idempotent payment processing system with in-memory storage. Single file, complete module. No external dependencies — OTP standard library only.

**`IdempotentPayments.start_link(opts)`**
- Starts the process.
- Accepts `:clock` — a zero-arity function returning the current time in milliseconds; default `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:ttl_ms` — how long idempotency keys are remembered; default 86,400,000 (24 hours).
- Accepts `:cleanup_interval_ms` — how often expired idempotency entries are purged via `Process.send_after`; default 60,000. Pass `:infinity` to disable automatic cleanup.

**`IdempotentPayments.process_payment(server, params, idempotency_key \\ nil)`**
- `params` is a map containing `:amount` (integer, cents), `:currency` (string), and `:recipient` (string).
- Behavior:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If `idempotency_key` is provided, seen before, and not yet expired, return `{:ok, response}` with the exact same response map returned the first time, without creating a duplicate payment record. This holds even if the replay carries different `params`.
  3. If `idempotency_key` is provided but has expired or was never seen, process the payment normally, cache the response keyed by the idempotency key with a fresh TTL, and return `{:ok, response}`.
  4. If required fields are missing from `params`, return `{:error, :invalid_params}`. If an idempotency key was provided, cache this error response too so replaying the same key returns the same error (even if the replay carries valid `params`), and no payment record is created.
- **Expiry:** an entry cached at clock time `T` expires at `T + ttl_ms`. It counts as a cache hit only while the current clock time is strictly less than that expiry; at exactly the expiry timestamp and after, the key is treated as expired. With `ttl_ms` of 10,000, a key cached at `t = 0` is still a hit at `t = 9_999` but is expired at `t = 10_000`.
- **`response` map fields:** `:id` (unique payment id string — see ID rule), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (the timestamp read from the clock at the moment the payment is processed).

**`IdempotentPayments.get_payments(server)`**
- Returns a list of all payment records stored, in creation order (oldest first), for test assertions about how many records were actually created.

**`IdempotentPayments.get_payment(server, id)`**
- Returns `{:ok, payment}` or `{:error, :not_found}`.

**Internal state**
- Each idempotency key entry stores the full response and the expiry timestamp.

**Cleanup**
- Periodic cleanup is triggered by a `:cleanup` message handled via `handle_info`.
- Removes only expired idempotency entries: an entry whose expiry timestamp is less than or equal to the current clock time counts as expired and is removed; one whose expiry is still strictly greater than the current time is kept.
- Payment records themselves are never cleaned up.

**Payment IDs**
- Sequential counter-based strings: `"pay_1"`, `"pay_2"`, `"pay_3"`, and so on.
- First payment record created is `"pay_1"`; the counter increments by exactly one per record in creation order.
- The counter is consumed only when a new payment record is actually created — idempotent cache hits and cached errors must not consume a number.
