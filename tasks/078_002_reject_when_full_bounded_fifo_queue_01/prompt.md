I need a pure-data-structure ring buffer from you — an Elixir module called `RejectingRingBuffer` that implements a fixed-size ring buffer as a plain struct with functions. No GenServer, please; I just want the data structure and its functions.

The twist versus a classic overwriting ring buffer: mine has to **reject** new items when it's full rather than silently discarding the oldest one. Think of it as a bounded FIFO queue — when it fills up, you `pop` items off the front to make room again.

Here's the public API I'm after:
- `RejectingRingBuffer.new(capacity)` — creates a new empty buffer with the given fixed capacity.
- `RejectingRingBuffer.push(buffer, item)` — attempts to insert an item at the back. It returns `{:ok, new_buffer}` on success, or `{:error, :full}` when the buffer is already at capacity, and in that failure case it does NOT mutate anything.
- `RejectingRingBuffer.pop(buffer)` — removes and returns the oldest item, giving back `{:ok, item, new_buffer}`, or `:empty` if the buffer holds no items.
- `RejectingRingBuffer.to_list(buffer)` — returns all current items in insertion order, oldest to newest; when the buffer is empty it returns `[]`.
- `RejectingRingBuffer.size(buffer)` — returns the number of items currently stored, from 0 up to capacity.
- `RejectingRingBuffer.full?(buffer)` — returns `true` when `size == capacity`, and `false` otherwise.
- `RejectingRingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if empty.
- `RejectingRingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if empty.

One thing I care about a lot: items may be any Elixir term, `nil` included. Store every pushed value verbatim — duplicates and `nil` are real stored entries, not empty slots — so `peek_oldest`/`peek_newest` on a stored `nil` must come back as `{:ok, nil}`, and emptiness must be decided purely by the `size`/`read`/`write` bookkeeping, never by a `nil` check.

On the internals, I want a fixed-size tuple pre-allocated to `capacity` slots as the backing store, with integer read/write head indices that wrap around using `rem/2`. Interleaving `push` and `pop` has to correctly reuse freed slots via that wraparound. Don't reach for a list or an `Enum`-grown structure as the primary store.

Send it back as the complete module in a single file, using only the Elixir standard library — no external dependencies.
