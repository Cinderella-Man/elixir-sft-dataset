Write me an Elixir module called `RingBuffer` that implements a fixed-size ring buffer as a pure data structure (no GenServer — just a plain struct with functions).

I need these functions in the public API:
- `RingBuffer.new(capacity)` — creates a new empty ring buffer with the given fixed capacity.
- `RingBuffer.push(buffer, item)` — inserts an item. When the buffer is full, it silently overwrites the oldest item.
- `RingBuffer.to_list(buffer)` — returns all current items in insertion order (oldest to newest).
- `RingBuffer.size(buffer)` — returns the number of items currently stored (not the capacity). This is 0 for an empty buffer and at most `capacity`.
- `RingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if the buffer is empty.
- `RingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if the buffer is empty.

The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with integer read/write head indices that wrap around using `rem/2`. Do not use a list or a `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.