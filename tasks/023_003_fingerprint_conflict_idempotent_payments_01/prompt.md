Hey — I need you to write me an Elixir GenServer module called `StrictIdempotentPayments`. The idea is to simulate an idempotent payment processing system with in-memory storage, but with a twist I care about a lot: request-fingerprint conflict detection. Here's the key behavioral difference from a naive idempotent endpoint — if someone replays an idempotency key with a *different request body*, I want that treated as a client error rather than silently returning the original cached response.

For the public API, start with `StrictIdempotentPayments.start_link(opts)`. It should accept `:clock` (a zero-arity ms clock, defaulting to `fn -> System.monotonic_time(:millisecond) end`), `:ttl_ms` (default 86,400,000), and `:cleanup_interval_ms` (default 60,000; passing `:infinity` disables the periodic `:cleanup` purge that otherwise runs via `Process.send_after`).

Then I need `StrictIdempotentPayments.process_payment(server, params, idempotency_key \\ nil)`, where `params` is a map carrying `:amount` (integer cents), `:currency` (string), and `:recipient` (string). Each stored idempotency entry should record the cached result, a fingerprint of the request params (compute it deterministically, e.g. `:erlang.phash2(params)`), and an expiry timestamp. An entry stored at clock time `T` expires at `T + ttl_ms`, and it counts as expired once the clock reaches that timestamp — so it's valid only while the current clock reading is strictly less than `T + ttl_ms`, meaning a replay at exactly `T + ttl_ms` gets processed fresh rather than served from cache. The semantics I want are:

1. If `idempotency_key` is `nil`, always create a new payment record and return `{:ok, response}`.
2. If the key has been seen and isn't expired and the current params fingerprint matches the stored one, return the exact cached result.
3. If the key has been seen and isn't expired but the params fingerprint differs, return `{:error, :idempotency_key_conflict}` — don't return the cached response, don't create a new record, and don't mutate the stored entry.
4. If the key is expired or unseen, process it normally (fingerprint the new params), cache the result under the key with a TTL, and return it.
5. If required fields are missing, return `{:error, :invalid_params}`; and when a key was provided, cache that error result along with its fingerprint — so a same-params replay returns the same error, while a different-params replay under that key is a conflict.

A successful `response` map should contain `:id` (a counter-based unique string; the first record created is `"pay_1"`, the next `"pay_2"`, and so on — the counter advances only when a record is actually created), `:amount`, `:currency`, `:recipient`, `:status` (always `"completed"`), and `:created_at` (the clock timestamp).

I also want `StrictIdempotentPayments.get_payments(server)` to return all payment records as a list, oldest first (an empty list when there are none), and `StrictIdempotentPayments.get_payment(server, id)` to return `{:ok, payment}` or `{:error, :not_found}`.

The periodic `:cleanup` should remove only expired idempotency entries (again, an entry is expired once the clock has reached its expiry timestamp); payment records must never be removed. And sending `:cleanup` to the server must never crash it. Please use only the OTP standard library, and give me the complete module in a single file.
