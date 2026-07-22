Write me an Elixir GenServer module called `IdempotentPayments` that simulates an idempotent payment processing system with in-memory storage.

I need these functions in the public API:

- `IdempotentPayments.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds (default to `fn -> System.monotonic_time(:millisecond) end`). It should also accept `:ttl_ms` for how long idempotency keys are remembered (default 86,400,000 — 24 hours), and `:cleanup_interval_ms` (default 60,000) controlling how often expired idempotency entries are purged via `Process.send_after`. Pass `:infinity` to disable automatic cleanup.

- `IdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map containing `:amount` (integer, cents), `:currency` (string), and `:recipient` (string). The function must:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If `idempotency_key` is provided and has been seen before (and hasn't expired), return `{:ok, response}` with the exact same response map that was returned the first time, without creating a duplicate payment record.
  3. If `idempotency_key` is provided but has expired or has never been seen, process the payment normally, cache the response keyed by the idempotency key with a TTL, and return `{:ok, response}`.
  4. If required fields are missing from `params`, return `{:error, :invalid_params}` — and if an idempotency key was provided, cache this error response too so that replaying the same key returns the same error.

  The `response` map must contain: `:id` (a unique string, e.g. a UUID), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (the timestamp from the clock).

- `IdempotentPayments.get_payments(server)` returns a list of all payment records stored (for test assertions about how many records were actually created).

- `IdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.

Each idempotency key entry in internal state should store the full response and the expiry timestamp. The periodic cleanup (triggered by a `:cleanup` message handled via `handle_info`) must remove only expired idempotency entries. Payment records themselves are never cleaned up.

Generate payment IDs using something simple and unique — a counter-based ID like `"pay_1"`, `"pay_2"`, etc. is fine so tests are deterministic. Do not pull in any external dependencies; use only OTP standard library.

Give me the complete module in a single file.