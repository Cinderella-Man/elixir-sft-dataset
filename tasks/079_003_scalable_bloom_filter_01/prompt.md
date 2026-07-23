# `ScalableBloomFilter` — Module Specification

## Overview

This document specifies an Elixir module called `ScalableBloomFilter` that implements a **scalable** Bloom filter — one that automatically grows so as to keep a bounded false-positive rate even when the number of inserted items greatly exceeds the initial guess.

A scalable Bloom filter is a list of ordinary Bloom-filter **slices**. Adds always go into the newest (active) slice. When the active slice reaches its capacity, a new, larger slice is appended with a *tighter* per-slice false-positive rate, so that the compound false-positive probability stays bounded no matter how many items arrive.

## Growth rules

The implementation uses these growth rules, with fixed constants: a capacity growth factor `s = 2` and an error tightening ratio `r = 0.5`. Given the caller's target rate `P`, the first slice's rate is set to `p0 = P * (1 - r)`. Slice `i` (0-indexed) then has:

- per-slice false-positive rate `p_i = p0 * r^i`
- capacity `capacity_i = initial_capacity * s^i`
- bit-array size `m_i = -ceil(capacity_i * ln(p_i) / (ln 2)^2)` and hash count `k_i = round(m_i / capacity_i * ln 2)`

## API

The public API consists of the following functions:

- `ScalableBloomFilter.new(initial_capacity, false_positive_rate)` — creates a filter with a single empty slice (index 0). `initial_capacity` is a positive integer; `false_positive_rate` is a float strictly between 0.0 and 1.0. The struct stores enough state to build further slices on demand and to track a total `count` of inserted items.
- `ScalableBloomFilter.add(filter, item)` — if the item has already been added, the filter is returned unchanged (this prevents duplicate inserts from inflating capacity). Otherwise the item's bits are set in the active slice and the total count is incremented; when the active slice reaches its capacity (its own item count is at least its capacity), a fresh larger slice is appended for future inserts. Returns the updated filter. Items may be any Elixir term.
- `ScalableBloomFilter.member?(filter, item)` — returns `true` if the item is present in **any** slice, and `false` only if it is absent from all of them (no false negatives). This is a probabilistic Bloom-filter query, so it may occasionally return `true` for an item that was never added.
- `ScalableBloomFilter.count(filter)` — the total number of distinct items inserted.
- `ScalableBloomFilter.num_slices(filter)` — the current number of slices (grows as the filter fills).

## Edge cases and constraints

- Duplicate detection in `add` must be **exact**: a genuinely new item must never be mistaken for a duplicate, even when the probabilistic membership query would report a false positive on it.
- The value reported by `count` is exact (unaffected by Bloom-filter false positives): it equals the number of genuinely distinct items passed to `add`.
- The `k` independent hashes per slice are derived from `:erlang.phash2/2` on a `{index, item}` tuple.
- Stdlib only — no external dependencies.
- The deliverable is the complete module in a single file.
