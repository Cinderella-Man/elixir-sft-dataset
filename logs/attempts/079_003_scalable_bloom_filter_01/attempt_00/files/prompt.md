Write me an Elixir module called `ScalableBloomFilter` that implements a **scalable** Bloom filter — one that automatically grows to keep a bounded false-positive rate even when the number of inserted items greatly exceeds the initial guess.

A scalable Bloom filter is a list of ordinary Bloom-filter **slices**. Adds always go into the newest (active) slice. When the active slice reaches its capacity, a new, larger slice is appended with a *tighter* per-slice false-positive rate, so the compound false-positive probability stays bounded no matter how many items arrive.

Use these growth rules (fixed constants): capacity growth factor `s = 2` and error tightening ratio `r = 0.5`. Given the caller's target rate `P`, set the first slice's rate to `p0 = P * (1 - r)`. Slice `i` (0-indexed) then has:
- per-slice false-positive rate `p_i = p0 * r^i`
- capacity `capacity_i = initial_capacity * s^i`
- bit-array size `m_i = -ceil(capacity_i * ln(p_i) / (ln 2)^2)` and hash count `k_i = round(m_i / capacity_i * ln 2)`

I need these functions in the public API:

- `ScalableBloomFilter.new(initial_capacity, false_positive_rate)` — creates a filter with a single empty slice (index 0). `initial_capacity` is a positive integer; `false_positive_rate` is a float strictly between 0.0 and 1.0. Store enough state in a struct to build further slices on demand and to track a total `count` of inserted items.
- `ScalableBloomFilter.add(filter, item)` — if the item is already a member, return the filter unchanged (this prevents duplicate inserts from inflating capacity). Otherwise set the item's bits in the active slice and increment its count; if the active slice is now at capacity, append a fresh larger slice for future inserts. Return the updated filter. Items may be any Elixir term.
- `ScalableBloomFilter.member?(filter, item)` — returns `true` if the item is present in **any** slice, `false` only if it is absent from all of them (no false negatives).
- `ScalableBloomFilter.count(filter)` — total number of distinct items inserted.
- `ScalableBloomFilter.num_slices(filter)` — the current number of slices (grows as the filter fills).

Derive `k` independent hashes per slice from `:erlang.phash2/2` on a `{index, item}` tuple. Stdlib only — no external dependencies. Give me the complete module in a single file.