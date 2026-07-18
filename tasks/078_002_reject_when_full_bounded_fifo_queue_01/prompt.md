Write me an Elixir module called `RejectingRingBuffer` that implements a fixed-size ring buffer as a pure data structure (no GenServer — just a plain struct with functions).

Unlike a classic overwriting ring buffer, this one **rejects** new items when it is full instead of silently discarding the oldest. It behaves as a bounded FIFO queue: you can `pop` items off the front to make room again.

I need these functions in the public API:
- `RejectingRingBuffer.new(capacity)` — creates a new empty buffer with the given fixed capacity.
- `RejectingRingBuffer.push(buffer, item)` — attempts to insert an item at the back. Returns `{:ok, new_buffer}` on success, or `{:error, :full}` (and does NOT mutate) when the buffer is already at capacity.
- `RejectingRingBuffer.pop(buffer)` — removes and returns the oldest item. Returns `{:ok, item, new_buffer}`, or `:empty` if the buffer holds no items.
- `RejectingRingBuffer.to_list(buffer)` — returns all current items in insertion order (oldest to newest); returns `[]` when empty.
- `RejectingRingBuffer.size(buffer)` — returns the number of items currently stored (0 to capacity).
- `RejectingRingBuffer.full?(buffer)` — returns `true` when `size == capacity`, else `false`.
- `RejectingRingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `RejectingRingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if empty.

Items may be any Elixir term, including `nil`. Store every pushed value verbatim: duplicates and `nil` are real stored entries (not empty slots), so `peek_oldest`/`peek_newest` on a stored `nil` must return `{:ok, nil}`, and only `size`/`read`/`write` bookkeeping — never a `nil` check — determines emptiness.

The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with integer read/write head indices that wrap around using `rem/2`. Interleaving `push` and `pop` must correctly reuse freed slots via wraparound. Do not use a list or an `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.
