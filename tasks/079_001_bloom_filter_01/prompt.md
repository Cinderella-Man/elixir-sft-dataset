Write me an Elixir module called `BloomFilter` that implements a space-efficient probabilistic data structure for set membership testing.

Stdlib only — no external dependencies — and give me the complete module in a single file.

## Struct

The filter is a struct `%BloomFilter{}` with exactly three fields, all of which are required (`@enforce_keys`):

- `:m` — the bit array size (positive integer)
- `:k` — the number of hash functions (positive integer)
- `:bits` — the bit array itself

Represent `:bits` as a **tuple of integers, where each integer is used as a 64-bit word**. The tuple has `ceil(m / 64)` elements, so bit index `i` lives at offset `rem(i, 64)` of word `div(i, 64)`. A freshly created filter has every word set to `0`. Because every bit index produced by hashing is `< m`, any trailing bits in the last word beyond `m` are never set and stay `0`.

Everything is purely functional: no function mutates its input struct.

## Public API

### `BloomFilter.new(expected_size, false_positive_rate)`

Creates a new, empty filter and derives the optimal parameters from the two arguments (`n = expected_size`, `p = false_positive_rate`):

- `m = ceil(-n * ln(p) / ln(2)^2)` — note the `ceil` applies to the whole expression, so `m` is always an integer ≥ 1.
- `k = max(1, round(m / n * ln(2)))` — the `max(1, …)` floor matters: for a very loose false-positive rate the rounded value can come out as `0`, and the filter must still use at least one hash function. E.g. `new(1_000, 0.9)` yields `m = 220` and `k = 1`.

A worked example of the normal case: `new(1_000, 0.01)` yields `m = 9586` and `k = 7` (and therefore `150` words in `:bits`).

`new/2` is total only on valid input: it accepts `expected_size` as a **positive integer** and `false_positive_rate` as a **float strictly between 0.0 and 1.0** (exclusive on both ends). Enforce this with guards and provide no fallback clause, so any other input (a zero or negative size, an integer rate, `0.0`, `1.0`, a rate outside that range) raises `FunctionClauseError` rather than returning an error tuple.

`new/2` is deterministic: two calls with the same arguments produce equal structs.

### `BloomFilter.add(filter, item)`

Hashes `item` with the `k` hash functions and sets the corresponding bits, returning an updated filter struct. The returned filter has the same `:m` and `:k`; only `:bits` may change. Observable semantics:

- `item` may be any Elixir term.
- Bits are only ever set, never cleared — the bit array grows monotonically.
- **Idempotent**: adding the same item twice returns a struct equal to the one produced by adding it once.
- **Order-independent**: adding a set of items in any order produces the same struct, so two filters built from the same items via different insertion orders are equal.

### `BloomFilter.member?(filter, item)`

Returns `true` if **all** `k` bits for `item` are set, `false` if any one of them is unset.

- No false negatives: if `item` was previously added to this filter (or to either input of a `merge` that produced it), this returns `true`, always.
- False positives are possible: it may return `true` for an item never added.
- On a freshly created filter every bit is `0` and `k ≥ 1`, so `member?/2` returns `false` for every item.
- It never modifies the filter; repeated calls with the same filter and item always give the same answer.

### `BloomFilter.merge(filter1, filter2)`

Combines two filters by OR-ing their bit arrays word by word, returning a filter with the same `:m` and `:k` and the union of both bit arrays. The result behaves as the union of the two item sets: `member?/2` returns `true` on the merged filter for every item that was added to either input.

- Both filters must have been created with the same parameters. If `m` or `k` differ, raise `ArgumentError` with a message that reports both filters' parameters, e.g. `"cannot merge filters with different parameters: filter1 has m=..., k=...; filter2 has m=..., k=..."`. (Matching `m` and `k` is the only compatibility check; equal parameters always merge.)
- Merging is commutative (`merge(a, b)` equals `merge(b, a)`), associative, and idempotent (`merge(a, a)` equals `a`).
- Merging any filter with an empty filter of the same parameters returns a filter equal to the non-empty one.
- Both arguments must be `%BloomFilter{}` structs; anything else raises `FunctionClauseError`.

## Hashing

Derive the `k` hash functions from a single primitive by seeding it with the function index: bit index for seed `i` (for `i` in `0..k-1`) is `:erlang.phash2({i, item}, m)`, which yields an integer in `0..m-1`. This makes hashing deterministic across calls, processes and filters with the same `m`: equal terms always map to the same bit indices, and terms that `:erlang.phash2/2` distinguishes (e.g. `1` and `1.0`, `"a"` and `:a`) generally map to different ones. Do not use any external dependency.
