# Engineering Design Brief — Sharded Parallel Reconciler

## Context

We reconcile two large lists of records by a shared composite key and emit a
structured diff. The single-process implementation is correct but scans everything
sequentially. This brief specifies a **parallel** reconciler that partitions the key
space into independent *shards*, runs each shard in its own worker process, and
composes the results — while remaining resilient to a shard that hangs or whose
user-supplied comparison callback blows up.

Deliver a single Elixir module named `ParallelReconciler`. It must rely only on the
standard library (it spawns processes, but pulls in no external dependencies).

## 1. Public API

Expose exactly one public function:

```
ParallelReconciler.reconcile_parallel(left, right, opts)
```

`left` and `right` are lists of maps; `opts` is a keyword list. The call is
synchronous from the caller's point of view: it blocks until every shard has
finished, timed out, or crashed, then returns a single result map (Section 6).

## 2. Options

* `:key_fields` (**required**) — a list of atoms forming the composite match key
  (e.g. `[:id]` or `[:org_id, :user_id]`).
* `:compare_fields` (optional) — a list of atoms naming the fields to diff on matched
  pairs. If omitted or `nil`, compare every field present in either record of a pair,
  minus the key fields.
* `:shards` (optional) — a **positive integer**, default `4`. The number of
  partitions the key space is divided into.
* `:timeout` (optional) — a **positive integer** number of milliseconds, default
  `5000`. The wall-clock budget granted to each shard's worker.
* `:compare` (optional) — a 3-arity callback `compare.(field, left_value, right_value)`.
  It must return a truthy value when the two values are considered **equal** for that
  field, and a falsy value (`false`/`nil`) otherwise. Default: `fn _field, a, b -> a == b end`.

## 3. Partitioning across shards

* For a record, let `K` be the tuple of its key-field values taken in `:key_fields`
  order (a one-element tuple for a single key field).
* That record is assigned to shard index `:erlang.phash2(K, shards)`, an integer in
  `0..shards - 1`.
* All records (from `left` and `right`) sharing a composite key land in the same
  shard, so any given key is reconciled entirely within one shard.
* Only shards that are assigned at least one record perform work. A shard that
  finishes contributes its results (Section 6) and appears in neither the timed-out
  nor the failed list.

## 4. Per-shard timeout and worker kill

* Each shard's reconciliation runs in a **separate worker process**, and all shard
  workers run concurrently.
* Each shard has `:timeout` milliseconds to complete.
* If a shard's worker does not finish within its budget, its worker process is
  **killed** (it must not be left running in the background), the shard contributes
  **nothing** to `:matched`, `:only_in_left`, or `:only_in_right`, and its shard index
  is recorded in `:timed_out_shards`. Any result the killed worker might otherwise
  have produced is discarded.

## 5. Callback failure isolation

* The `:compare` callback is user-supplied and may raise.
* If the callback raises while a shard is being processed, only **that shard's**
  worker crashes. The overall `reconcile_parallel/3` call must **not** crash: it
  returns normally. The crashed shard contributes nothing to `:matched`,
  `:only_in_left`, or `:only_in_right`, and its shard index is recorded in
  `:failed_shards`.
* A crash or timeout in one shard must not prevent other shards from completing and
  contributing their results.

## 6. Result shape

`reconcile_parallel/3` returns a map with exactly these keys:

* `:matched` — a list of `%{left: record, right: record, differences: diff_map}`
  entries, one per key present in **both** lists (across all shards that completed).
  `diff_map` is a map `%{field => %{left: val, right: val}}` for every compared field
  the two records are **not** equal on (per Section 7). It is `%{}` when the records
  are equal on all compared fields. Each entry carries the **full** original `left`
  and `right` records, even for fields excluded from comparison.
* `:only_in_left` — records whose key appears only in `left` (from completed shards).
* `:only_in_right` — records whose key appears only in `right` (from completed shards).
* `:timed_out_shards` — the shard indexes that exceeded `:timeout`, each listed at
  most once, in ascending order.
* `:failed_shards` — the shard indexes whose worker crashed because `:compare` raised,
  each listed at most once, in ascending order.

The order of elements within `:matched`, `:only_in_left`, and `:only_in_right` is
unspecified.

## 7. Comparison semantics

* Key matching is exact: two records match iff every key field is equal (`==`). A
  composite key matches only when **all** its fields are equal.
* For each compared field of a matched pair, `:compare` is invoked as
  `compare.(field, left_value, right_value)`. A truthy result means "equal" (no
  difference); a falsy result records `%{field => %{left: left_value, right: right_value}}`.
* If a compared field is missing from a record, treat its value as `nil` and pass
  `nil` to the callback / comparison.

## 8. Validation

Validate `:key_fields` **before** doing any work: if it is missing, `nil`, not a
list, an empty list, or contains any non-atom element, raise `ArgumentError`.
If `:shards` is provided but is not a positive integer, raise `ArgumentError`.
If `:timeout` is provided but is not a positive integer, raise `ArgumentError`.

## 9. Constraints

* Standard library only; no external dependencies.
* The result for a given input must be identical regardless of `:shards` (the shard
  count is a performance knob, not a semantic one).