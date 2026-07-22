Write me an Elixir module called `ConcurrentRingBuffer` that implements a fixed-size overwriting ring buffer as a **GenServer**, so it can be shared safely across many concurrent processes (e.g. as a live log tail or a metrics sink).

Push semantics match a classic ring buffer: when the buffer is full, the oldest item is silently overwritten. All operations are serialized through the GenServer so concurrent writers never corrupt the buffer.

I need this public API (each function takes the server pid or registered name as its first argument):
- `ConcurrentRingBuffer.start_link(opts)` — starts the server. `opts` is a keyword list that MUST include `:capacity` (a positive integer) and MAY include `:name` for registration. Returns `{:ok, pid}`.
- `ConcurrentRingBuffer.push(server, item)` — inserts an item, overwriting the oldest when full. Returns `:ok`.
- `ConcurrentRingBuffer.to_list(server)` — returns all current items in insertion order (oldest to newest).
- `ConcurrentRingBuffer.size(server)` — returns the number of items currently stored (0 to capacity).
- `ConcurrentRingBuffer.peek_oldest(server)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `ConcurrentRingBuffer.peek_newest(server)` — returns `{:ok, item}` for the newest item, or `:error` if empty.
- `ConcurrentRingBuffer.flush(server)` — atomically returns all current items (oldest to newest) AND empties the buffer in a single operation, so a draining consumer never loses or double-reads items.

Internally the server state must store items in a fixed-size tuple (pre-allocated to `capacity` slots) with integer read/write head indices that wrap around using `rem/2`. Do not use a list or an `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library (and OTP's `GenServer`) — no external dependencies.