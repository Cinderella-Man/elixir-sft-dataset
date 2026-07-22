# Schema Inference from CSV — Chunked Merge-Based Inference

Write me an Elixir module called `MergeSchema` that infers CSV column types, but is built so a large file can be inferred **in independent chunks that are merged**. Each chunk is reduced to a compact *partial* inference state; partials combine with an associative, commutative, idempotent `merge/2`; and a final resolution step turns a partial into a schema. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

- `MergeSchema.partial(csv, opts \\ [])` — parse a CSV fragment and return an opaque **partial** inference state (a plain map).
- `MergeSchema.merge(partial_a, partial_b)` — combine two partials into one.
- `MergeSchema.finalize(partial)` — resolve a partial into a schema map `%{"column_name" => :inferred_type}`.
- `MergeSchema.infer_string(csv, opts \\ [])` — convenience: `finalize(partial(csv, opts))`.

The inferred type is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`.

### Options (for `partial/2` and `infer_string/2`)

- `:headers` (boolean, default `true`) — when `true`, the **first record of that fragment** is a header row supplying column names; when `false`, all records are data and columns are positional (`"column_1"`, `"column_2"`, …, 1-indexed).

There is no `:sample_rows` option — a chunk is expected to already be a bounded slice of the file.

## Partial representation

A partial must be a plain map with exactly these keys:

- `:names` — the list of header column-name strings for this fragment, or `nil` when the fragment was parsed with `headers: false`. A fragment with **no records at all** (an empty string, or only a trailing newline) has no header row to consume, so its `:names` is `nil` — never `[]` — its `:ncols` is `0`, and its `:categories` is empty. That makes the empty-fragment partial a **neutral element** for `merge/2`: merging it with any partial `p`, in either order, must finalize exactly like `p` alone (an empty fragment must never mask the header carried by another chunk).
- `:ncols` — the number of columns observed (the max over the header length and every data row's field count).
- `:categories` — a map from 0-based column index to a `MapSet` of the **non-null cell categories** seen in that column (nulls are never added).

## CSV parsing rules

RFC-4180 style, identical to the base task: `\n` record separator with a single trailing newline ignored; comma field separator; double-quoted fields may contain commas; doubled quotes (`""`) are a literal quote; track whether each field was quoted. An **unquoted empty field** is null (ignored); a quoted empty field (`""`) is a non-null empty string value.

## Per-cell categories

For each non-null cell, classify exactly as in the base task: quoted fields are always `string`; otherwise `boolean` (`true`/`false`, case-insensitive), `integer` (`^[+-]?\d+$`), `float` (`^[+-]?\d+\.\d+$`), `date` (valid `YYYY-MM-DD` or `MM/DD/YYYY`), `datetime` (valid `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS`), else `string`. Values are used verbatim.

## Merge semantics

`merge/2` must be **associative, commutative, and idempotent**:

- `:categories` — per-index `MapSet` union.
- `:ncols` — the maximum of the two.
- `:names` — the first non-`nil` of the two (`a.names || b.names`). In practice only one fragment (the first chunk) carries a header.

## Finalization

`finalize/1` resolves each column from its accumulated category set, using the base task's rules:

1. Empty set (all null / no data) → `:string`.
2. Exactly one category → that category.
3. A set that is a subset of `{integer, float}` → `:float`.
4. Otherwise → `:string`.

Column names come from `:names` when present; otherwise positional names `"column_1"`..`"column_ncols"` are generated from `:ncols`.