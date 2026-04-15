Write me an Elixir module called `BloomFilter` that implements a space-efficient probabilistic data structure for set membership testing.

I need these functions in the public API:
- `BloomFilter.new(expected_size, false_positive_rate)` which creates a new filter. It must automatically calculate the optimal bit array size (`m`) and number of hash functions (`k`) from the two parameters. `expected_size` is the anticipated number of items to be inserted, and `false_positive_rate` is a float between 0.0 and 1.0 (e.g. `0.01` for 1%). Store these as a struct.
- `BloomFilter.add(filter, item)` which hashes the item using `k` different hash functions and sets the corresponding bits. It must return an updated filter struct. Items can be any Elixir term.
- `BloomFilter.member?(filter, item)` which returns `true` if all `k` bits for this item are set, and `false` if any bit is unset. It must never return `false` for an item that was previously added (no false negatives), but may return `true` for items that were never added (false positives).
- `BloomFilter.merge(filter1, filter2)` which combines two filters by OR-ing their bit arrays together. Both filters must have been created with the same parameters — raise `ArgumentError` if `m` or `k` differ.

For hashing, derive `k` independent hash functions from a single `:erlang.phash2/2` or similar by seeding it differently for each function index (e.g. hashing a `{index, item}` tuple). Do not use any external dependency — stdlib only.

Give me the complete module in a single file with no external dependencies.