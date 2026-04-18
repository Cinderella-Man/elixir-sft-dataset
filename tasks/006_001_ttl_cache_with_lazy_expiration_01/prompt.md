Write me an Elixir GenServer module called `TTLCache` that stores key-value pairs with per-key time-to-live (TTL) expiration, using lazy expiration on reads plus a periodic sweep for unread keys.

I need these functions in the public API:

- `TTLCache.start_link(opts)` to start the process. It should accept a `:clock` option which is a zero-arity function returning the current time in milliseconds. If not provided, default to `fn -> System.monotonic_time(:millisecond) end`. It should also accept a `:name` option for process registration and a `:sweep_interval_ms` option (default 60_000) controlling how often a periodic sweep runs to remove all expired entries.

- `TTLCache.put(server, key, value, ttl_ms)` which stores a key-value pair that expires after `ttl_ms` milliseconds from the time of insertion. If the key already exists, overwrite both its value and its expiration. Returns `:ok`.

- `TTLCache.get(server, key)` which looks up a key. If the key exists and has not expired, return `{:ok, value}`. If the key does not exist or has expired, return `:miss`. Expired keys must be lazily deleted from internal state on read so they don't linger.

- `TTLCache.delete(server, key)` which explicitly removes a key regardless of whether it has expired. Returns `:ok` whether the key existed or not.

Each key is independent — putting or deleting key "a" must have no effect on key "b". A `put` with a new TTL on an existing key resets that key's expiration entirely based on the current time plus the new TTL.

You also need to prevent memory leaks from keys that are written but never read again. Use `Process.send_after` to schedule a `:sweep` message every `:sweep_interval_ms` milliseconds. When the sweep runs, remove all entries whose expiration time is in the past. The sweep should reschedule itself after completing.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.