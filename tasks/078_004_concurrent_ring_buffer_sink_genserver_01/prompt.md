I need a module from you — `ConcurrentRingBuffer` — a fixed-size overwriting ring buffer implemented as a **GenServer** so we can share one instance safely across a bunch of concurrent processes (I'm thinking live log tail, or a metrics sink).

Push semantics are the classic ring buffer ones: once the buffer is full, the oldest item gets silently overwritten. Everything goes through the GenServer, so all operations are serialized and concurrent writers can never corrupt the buffer.

Here's the public API I need. Every function takes the server pid or registered name as its first argument:

- `ConcurrentRingBuffer.start_link(opts)` — starts the server. `opts` is a keyword list that MUST include `:capacity` (a positive integer) and MAY include `:name` for registration. Returns `{:ok, pid}`.
- `ConcurrentRingBuffer.push(server, item)` — inserts an item, overwriting the oldest when full. Returns `:ok`.
- `ConcurrentRingBuffer.to_list(server)` — returns all current items in insertion order (oldest to newest).
- `ConcurrentRingBuffer.size(server)` — returns the number of items currently stored (0 to capacity).
- `ConcurrentRingBuffer.peek_oldest(server)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `ConcurrentRingBuffer.peek_newest(server)` — returns `{:ok, item}` for the newest item, or `:error` if empty.
- `ConcurrentRingBuffer.flush(server)` — atomically returns all current items (oldest to newest) AND empties the buffer in a single operation, so a draining consumer never loses or double-reads items.

On the internals, I'm particular here: the server state must store items in a fixed-size tuple, pre-allocated to `capacity` slots, with integer read/write head indices that wrap around using `rem/2`. Please don't use a list or an `Enum`-grown structure as the primary store.

Send me the complete module in a single file. Stick to the Elixir standard library (plus OTP's `GenServer`) — no external dependencies.
