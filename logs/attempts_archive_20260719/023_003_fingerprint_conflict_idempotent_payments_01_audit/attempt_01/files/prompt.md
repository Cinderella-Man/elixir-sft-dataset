Write me an Elixir GenServer module called `StrictIdempotentPayments` that simulates an idempotent payment processing system with in-memory storage **and request-fingerprint conflict detection**. The key behavioral difference from a naive idempotent endpoint: replaying an idempotency key with a *different request body* is treated as a client error rather than silently returning the original cached response.

Public API:

- `StrictIdempotentPayments.start_link(opts)` accepting `:clock` (zero-arity ms clock, default `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` (default 86,400,000), and `:cleanup_interval_ms` (default 60,000; `:infinity` disables the periodic `:cleanup` purge via `Process.send_after`).

- `StrictIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)` where `params` is a map with `:amount` (integer cents), `:currency` (string), `:recipient` (string). Each stored idempotency entry records the cached result, a **fingerprint** of the request params (compute it deterministically, e.g. `:erlang.phash2(params)`), and an expiry timestamp. Semantics:
  1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
  2. If the key has been seen and is not expired **and the current params fingerprint matches the stored one**, return the exact cached result.
  3. If the key has been seen and is not expired **but the params fingerprint differs**, return `{:error, :idempotency_key_conflict}` — do NOT return the cached response, do NOT create a new record, and do NOT mutate the stored entry.
  4. If the key is expired or unseen, process normally (fingerprint the new params), cache the result under the key with a TTL, and return it.
  5. If required fields are missing, return `{:error, :invalid_params}`; when a key was provided, cache that error result along with its fingerprint (so a same-params replay returns the same error, while a different-params replay under that key is a conflict).

  A successful `response` map contains `:id` (counter-based unique string like `"pay_1"`), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (clock timestamp).

- `StrictIdempotentPayments.get_payments(server)` returns all payment records (oldest first).
- `StrictIdempotentPayments.get_payment(server, id)` returns `{:ok, payment}` or `{:error, :not_found}`.

The periodic `:cleanup` removes only expired idempotency entries; payment records are never removed. Use only the OTP standard library. Give me the complete module in a single file.