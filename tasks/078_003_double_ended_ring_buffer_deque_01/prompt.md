I need a bounded deque for one of our hot paths, and I'd like it as a plain Elixir module called `RingDeque` — a fixed-size, double-ended ring buffer implemented as a pure data structure. No GenServer, please; just a plain struct with functions.

The behavior I'm after: items can be pushed onto either end, and when the deque is full, pushing to one end silently overwrites the element at the OPPOSITE end. So a push to the back drops the front, and a push to the front drops the back.

Here's the public API I need:

- `RingDeque.new(capacity)` — creates a new empty deque with the given fixed capacity.
- `RingDeque.push_back(deque, item)` — appends at the back. When full, overwrites (drops) the current front.
- `RingDeque.push_front(deque, item)` — prepends at the front. When full, overwrites (drops) the current back.
- `RingDeque.pop_front(deque)` — removes and returns the front item. Returns `{:ok, item, deque}`, or `:empty`.
- `RingDeque.pop_back(deque)` — removes and returns the back item. Returns `{:ok, item, deque}`, or `:empty`.
- `RingDeque.to_list(deque)` — returns all current items in order from front to back.
- `RingDeque.size(deque)` — returns the number of items currently stored (0 to capacity).
- `RingDeque.peek_front(deque)` — returns `{:ok, item}` for the front item, or `:error` if empty.
- `RingDeque.peek_back(deque)` — returns `{:ok, item}` for the back item, or `:error` if empty.

On the internals, I'm particular here: the representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with an integer head index and a live-count, both advancing with `rem/2` so all four operations wrap around the tuple in O(1). Don't reach for a list or an `Enum`-grown structure as the primary store.

Send me the complete module in a single file, using only the Elixir standard library — no external dependencies.
