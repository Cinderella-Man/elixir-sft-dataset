# Specification: `CountingBloomFilter` — A Deletable Probabilistic Set

## Overview

This document specifies an Elixir module named `CountingBloomFilter` that implements a **counting** Bloom filter: a probabilistic set-membership structure which, unlike a classic Bloom filter, also supports **deletion**.

Where a classic Bloom filter uses a bit array, a counting Bloom filter maintains an array of small integer **counters**. Adding an item increments its `k` counters; removing an item decrements them. An item is considered a member for as long as all `k` of its counters are greater than zero.

The structure is stored in a struct defined exactly as `defstruct [:m, :k, :counters, :size]`, holding the counter-array size `m`, the number of hash functions `k`, the counter array, and a running `size` (the number of live items). The `:counters` field holds the `m` counters as a **tuple**, each counter being an integer in `0..255`.

## API

The public API consists of the following functions.

### `CountingBloomFilter.new(expected_size, false_positive_rate)`

Creates a new filter. It must automatically calculate the optimal counter-array size (`m`) and number of hash functions (`k`) from the two parameters, using the same formulas as a standard Bloom filter:

- `m = -ceil(n * ln p / (ln 2)^2)`
- `k = round(m/n * ln 2)`

`expected_size` is the anticipated number of live items. `false_positive_rate` is a float strictly between 0.0 and 1.0.

### `CountingBloomFilter.add(filter, item)`

Hashes the item with `k` derived hash functions and increments the corresponding counters, returning an updated filter. Items may be any Elixir term.

### `CountingBloomFilter.remove(filter, item)`

If the item is currently a member, this decrements its `k` counters and decrements `size`. If it is not a member, the filter is returned unchanged.

### `CountingBloomFilter.member?(filter, item)`

Returns `true` if all `k` counters for the item are greater than zero, and `false` otherwise.

### `CountingBloomFilter.count(filter)`

Returns the current number of live items (`size`).

### `CountingBloomFilter.merge(filter1, filter2)`

Combines two filters by **summing** their counter arrays element-wise and summing their sizes.

## Hashing

The `k` independent hash functions are derived from `:erlang.phash2/2` by hashing a `{index, item}` tuple.

## Edge cases

- **Saturation on add.** Counters saturate at 255 and must never overflow past it.
- **Multiset insert.** Adding the same item twice is a multiset insert: its counters go to 2.
- **Floor on remove.** Decrementing must never take a counter below zero.
- **Saturated counters are frozen.** To preserve the no-false-negatives guarantee, a counter that has **saturated** at 255 must never be decremented.
- **Removing a non-member.** Such a call returns the filter unchanged.
- **Membership guarantees.** `CountingBloomFilter.member?/2` must never return `false` for an item that is currently in the set (no false negatives), but it may return `true` for items never added (false positives).
- **Merge saturation.** Element-wise counter sums saturate at 255.
- **Merge compatibility.** Both filters must have been created with identical `m` and `k`; otherwise `ArgumentError` must be raised.

## Deliverable

The complete module, in a single file. Stdlib only — no external dependencies.
