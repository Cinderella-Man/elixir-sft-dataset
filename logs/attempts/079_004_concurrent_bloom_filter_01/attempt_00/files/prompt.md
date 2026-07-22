Write me an Elixir module called `ConcurrentBloomFilter` that implements a **lock-free, concurrently-writable** Bloom filter backed by Erlang's `:atomics` module, so that many processes can add items in parallel without any GenServer, locks, or message passing.

Unlike a purely functional Bloom filter, this one holds a single shared, mutable `:atomics` array (one 1-bit slot per position). Because a slot is only ever *set* to `1` (never cleared) and `:atomics.put/3` is atomic, concurrent writers cannot corrupt each other or lose updates — no compare-and-swap loop is needed.

I need these functions in the public API:

- `ConcurrentBloomFilter.new(expected_size, false_positive_rate)` — creates a new filter. It must compute the optimal array size (`m = -ceil(n * ln p / (ln 2)^2)`) and hash count (`k = round(m/n * ln 2)`), allocate a `:atomics` array of `m` unsigned slots, and return a struct holding `m`, `k`, and the atomics reference. `expected_size` is a positive integer; `false_positive_rate` is a float strictly between 0.0 and 1.0.
- `ConcurrentBloomFilter.add(filter, item)` — hashes the item with `k` derived hash functions and atomically sets each corresponding slot to `1`. Because the backing store is shared and mutable, this update is visible to every process holding the same filter handle. Return the (unchanged) filter handle. Items may be any Elixir term. This must be safe to call concurrently from many processes.
- `ConcurrentBloomFilter.member?(filter, item)` — returns `true` if all `k` slots for the item read as `1`, `false` if any is `0`. No false negatives for items that were added.
- `ConcurrentBloomFilter.merge(into, from)` — ORs `from`'s array into `into`'s array in place (setting any slot in `into` whose corresponding slot in `from` is `1`), and returns `into`. Both filters must have identical `m` and `k` — raise `ArgumentError` otherwise.

Derive `k` independent hashes from `:erlang.phash2/2` on a `{index, item}` tuple. Note that `:atomics` indices are 1-based. Stdlib/OTP only — no external dependencies. Give me the complete module in a single file.