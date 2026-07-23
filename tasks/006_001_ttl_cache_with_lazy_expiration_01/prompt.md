# TTLCache — GenServer key-value store with per-key TTL expiration

Implement an Elixir GenServer module `TTLCache` for key-value pairs with per-key time-to-live (TTL) expiration, using lazy expiration on reads plus a periodic sweep for unread keys. Deliver the complete module in a single file. Use only the OTP standard library — no external dependencies.

**Expiration model**
- An entry inserted at insertion-time with `ttl_ms` expires at insertion-time + `ttl_ms`.
- The entry is live only while the current time (per `:clock`) is strictly before that expiration instant; at or after that instant the key is expired.
- Keys are independent: putting or deleting key "a" must have no effect on key "b".
- A `put` with a new TTL on an existing key resets that key's expiration entirely, based on the current time plus the new TTL.

**Public API — `TTLCache.start_link(opts)`**
- Starts the process; returns `{:ok, pid}` on success.
- Accepts `:clock`, a zero-arity function returning the current time in milliseconds. Default: `fn -> System.monotonic_time(:millisecond) end`.
- Accepts `:name` for process registration.
- Accepts `:sweep_interval_ms` (default 60_000) controlling how often the periodic sweep runs to remove all expired entries.
- `:sweep_interval_ms` may also be `:infinity`, in which case the periodic timer is never scheduled — nothing runs automatically.

**Public API — `TTLCache.put(server, key, value, ttl_ms)`**
- Stores a key-value pair that expires after `ttl_ms` milliseconds from the time of insertion.
- If the key already exists, overwrite both its value and its expiration.
- Returns `:ok`.

**Public API — `TTLCache.get(server, key)`**
- If the key exists and has not expired, return `{:ok, value}`.
- If the key does not exist or has expired, return `:miss`.
- Expired keys must be lazily deleted from internal state on read so they don't linger.

**Public API — `TTLCache.delete(server, key)`**
- Explicitly removes a key regardless of whether it has expired.
- Returns `:ok` whether the key existed or not.

**Periodic sweep**
- Prevent memory leaks from keys that are written but never read again.
- Use `Process.send_after` to schedule a `:sweep` message every `:sweep_interval_ms` milliseconds.
- When the sweep runs, remove all entries whose expiration time is in the past.
- The sweep must reschedule itself after completing.
- Handling a `:sweep` message must remove expired entries whether it arrived from the scheduled timer or was sent to the process directly, and must not disrupt subsequent `put`/`get`/`delete` operations.
