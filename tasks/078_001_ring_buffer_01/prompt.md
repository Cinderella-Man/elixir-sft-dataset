# Design brief: `RingBuffer`

## Problem

We need a fixed-size ring buffer in Elixir — the kind of structure that holds the last N items and quietly discards older ones as new data arrives. It must be a pure data structure: no GenServer, no process, just a plain struct with functions operating on it.

## Constraints

- The internal representation must use a fixed-size tuple (pre-allocated to `capacity` slots) as the backing store, with integer read/write head indices that wrap around using `rem/2`.
- Do not use a list or a `Enum`-grown structure as the primary store.
- Only the Elixir standard library may be used — no external dependencies.
- The deliverable is the complete module in a single file.

## Required interface

The public API must consist of these functions:

1. `RingBuffer.new(capacity)` — creates a new empty ring buffer with the given fixed capacity.
2. `RingBuffer.push(buffer, item)` — inserts an item. When the buffer is full, it silently overwrites the oldest item.
3. `RingBuffer.to_list(buffer)` — returns all current items in insertion order (oldest to newest).
4. `RingBuffer.size(buffer)` — returns the number of items currently stored (not the capacity). This is 0 for an empty buffer and at most `capacity`.
5. `RingBuffer.peek_oldest(buffer)` — returns `{:ok, item}` for the oldest item, or `:error` if the buffer is empty.
6. `RingBuffer.peek_newest(buffer)` — returns `{:ok, item}` for the most recently pushed item, or `:error` if the buffer is empty.

## Acceptance criteria

- A module named `RingBuffer` exists and implements the fixed-size ring buffer as a plain struct with functions — not a GenServer.
- All six functions above are present in the public API and behave exactly as described, including the overwrite-oldest behavior on a full buffer, the oldest-to-newest ordering of `RingBuffer.to_list(buffer)`, the 0-to-`capacity` range of `RingBuffer.size(buffer)`, and the `{:ok, item}` / `:error` returns of the two peek functions.
- The backing store is a fixed-size tuple pre-allocated to `capacity` slots, indexed by integer read/write heads that wrap via `rem/2`; no list or `Enum`-grown structure serves as the primary store.
- Everything ships as one file, standard library only.
