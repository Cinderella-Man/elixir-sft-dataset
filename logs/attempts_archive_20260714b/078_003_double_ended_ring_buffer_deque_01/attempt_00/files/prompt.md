Write me an Elixir module called `RingDeque` that implements a fixed-size, double-ended ring buffer (a bounded deque) as a pure data structure (no GenServer — just a plain struct with functions).

Items can be pushed onto either end. When the deque is full, pushing to one end silently overwrites the element at the OPPOSITE end (push to the back drops the front; push to the front drops the back).

I need these functions in the public API:
- `RingDeque.new(capacity)` — creates a new empty deque with the given fixed capacity.
- `RingDeque.push_back(deque, item)` — appends at the back. When full, overwrites (drops) the current front.
- `RingDeque.push_front(deque, item)` — prepends at the front. When full, overwrites (drops) the current back.
- `RingDeque.pop_front(deque)` — removes and returns the front item. Returns `{:ok, item, deque}`, or `:empty`.
- `RingDeque.pop_back(deque)` — removes and returns the back item. Returns `{:ok, item, deque}`, or `:empty`.
- `RingDeque.to_list(deque)` — returns all current items in order from front to back.
- `RingDeque.size(deque)` — returns the number of items currently stored (0 to capacity).
- `RingDeque.peek_front(deque)` — returns `{:ok, item}` for the front item, or `:error` if empty.
- `RingDeque.peek_back(deque)` — returns `{:ok, item}` for the back item, or `:error` if empty.

The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with an integer head index and a live-count, both advancing with `rem/2` so all four operations wrap around the tuple in O(1). Do not use a list or an `Enum`-grown structure as the primary store.

Give me the complete module in a single file. Use only the Elixir standard library — no external dependencies.