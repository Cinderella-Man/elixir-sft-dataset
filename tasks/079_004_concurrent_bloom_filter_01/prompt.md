I need a module from you — `ConcurrentBloomFilter` — and the thing I care about most is that it's a **lock-free, concurrently-writable** Bloom filter sitting on top of Erlang's `:atomics` module. The whole point is that a pile of processes can add items in parallel without any GenServer, without locks, and without message passing.

So this isn't the purely functional Bloom filter you'd normally write. It holds one shared, mutable `:atomics` array, one 1-bit slot per position. The reason we can get away with no compare-and-swap loop is that a slot is only ever *set* to `1` and never cleared, and `:atomics.put/3` is atomic — so concurrent writers can't corrupt each other or lose updates.

Here's the public API I'm after:

`ConcurrentBloomFilter.new(expected_size, false_positive_rate)` creates a new filter. It has to compute the optimal array size (`m = -ceil(n * ln p / (ln 2)^2)`) and the hash count (`k = round(m/n * ln 2)`), allocate an `:atomics` array of `m` unsigned slots, and hand back a struct holding `m`, `k`, and the atomics reference. Assume `expected_size` is a positive integer and `false_positive_rate` is a float strictly between 0.0 and 1.0.

`ConcurrentBloomFilter.add(filter, item)` hashes the item with `k` derived hash functions and atomically sets each corresponding slot to `1`. Since the backing store is shared and mutable, that update needs to be visible to every process holding the same filter handle. Return the filter handle back, unchanged. Items can be any Elixir term. And this one specifically has to be safe to call concurrently from many processes.

`ConcurrentBloomFilter.member?(filter, item)` returns `true` when all `k` slots for the item read as `1`, and `false` if any of them is `0`. No false negatives for anything that was actually added.

`ConcurrentBloomFilter.merge(into, from)` ORs `from`'s array into `into`'s array in place — i.e. set any slot in `into` whose corresponding slot in `from` is `1` — and returns `into`. Both filters have to have identical `m` and `k`; raise `ArgumentError` if they don't.

For the hashing, derive the `k` independent hashes from `:erlang.phash2/2` over a `{index, item}` tuple. Watch out that `:atomics` indices are 1-based. Stdlib/OTP only, no external dependencies please. Send me the complete module in a single file.
