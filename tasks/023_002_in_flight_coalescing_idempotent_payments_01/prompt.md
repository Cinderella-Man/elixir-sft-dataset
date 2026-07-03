Write me an Elixir GenServer module called `CoalescingPayments` that simulates an idempotent payment processing system with in-memory storage **and in-flight request coalescing**. Unlike a plain idempotent endpoint, the defining property here is the concurrency model: when several callers hit the same idempotency key *while the first one is still being processed*, only ONE payment is processed and all the concurrent waiters receive that single shared result.

Public API:

- `CoalescingPayments.start_link(opts)` to start the process. It should accept a `:clock` option (zero-arity function returning current time in milliseconds, default `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` for how long completed idempotency keys are remembered (default 86,400,000), `:cleanup_interval_ms` (default 60,000, controlling periodic purge of expired *completed* entries via `Process.send_after`; `:infinity` disables it), and `:processor` — a one-arity function that receives `params` and returns `:ok` (payment accepted) or `{:error, reason}` (gateway declined). This function simulates the slow external call and defaults to `fn _params -> :ok end`.

- `CoalescingPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), and `:recipient` (string). Semantics:
  1. If `idempotency_key` is `nil`, always process a new payment (each call runs the processor independently) and return `{:ok, response}` or `{:error, reason}`.
  2. If the key is already **completed** (cached, not expired), return the exact same cached result without re-running the processor.
  3. If the key is currently **in flight** (another caller triggered processing that hasn't finished), the caller must block until that processing completes and then receive the same result — the processor must run exactly once for the whole group.
  4. If the key is expired or unseen, start processing.
  5. If required fields are missing, return `{:error, :invalid_params}` immediately (no processor call) and, when a key was given, cache that error result too.

  The GenServer must NOT block inside the processor — run the processor work in a spawned process and reply to all waiting callers via `GenServer.reply/2` when it finishes. A successful result builds a `response` map with `:id` (unique string like `"pay_1"`, counter-based), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (timestamp from the clock).

- `CoalescingPayments.get_payments(server)` returns all payment records (oldest first).
- `CoalescingPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.
- `CoalescingPayments.in_flight_count(server)` returns how many payments are currently being processed (pending, not yet replied).

Payment records are never cleaned up; only expired *completed* idempotency entries are purged on the `:cleanup` message. Use only the OTP standard library; no external dependencies. Give me the complete module in a single file.