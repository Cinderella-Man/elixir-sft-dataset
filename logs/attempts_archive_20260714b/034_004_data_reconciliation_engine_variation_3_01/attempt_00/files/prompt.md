Write me an Elixir module called `ConcurrentReconciler` that reconciles two large
lists of records by a shared key, producing the same structured diff as an ordinary
reconciler, but computing the per-record field diffs **concurrently** across a pool
of worker tasks so it can take advantage of multiple schedulers.

I need this public API:

- `ConcurrentReconciler.reconcile(left, right, opts)` where `left` and `right` are
  lists of maps and `opts` is a keyword list. It returns a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}`
    entries for keys present in both lists. `diff_map` is `%{field => %{left: val, right: val}}`
    for fields whose values differ, empty if identical on all compared fields.
  - `:only_in_left` — records present in `left` but absent in `right`.
  - `:only_in_right` — records present in `right` but absent in `left`.

The `opts` keyword list must support:
- `:key_fields` (required) — a list of atoms forming the composite key used to match
  records (e.g. `[:id]` or `[:org_id, :user_id]`).
- `:compare_fields` (optional) — a list of atoms specifying which fields to diff on
  matched records. If omitted or `nil`, all fields except the key fields are compared.
- `:max_concurrency` (optional) — a positive integer bounding how many matched-record
  diffs run in parallel. Defaults to `System.schedulers_online()`.

Behaviour requirements:
- The result must be **identical in content** to a sequential reconciliation — the
  concurrency must not change which records are matched or how they differ. Order of
  results does not matter.
- Key matching must be exact; composite keys require all key fields to be equal.
- Field comparison must be value-exact (using `==`), and a field missing from one or
  both records is treated as `nil`.
- Matched entries must carry the full original left and right records.
- `:max_concurrency` must be honoured as an upper bound; an invalid value (not a
  positive integer) must raise `ArgumentError`.
- The diff computation for matched records must be spread across worker tasks (e.g.
  via `Task.async_stream`); the function may use processes internally, but must have
  no other side effects and no external dependencies beyond the Elixir/OTP standard
  library.

Give me the complete module in a single file.