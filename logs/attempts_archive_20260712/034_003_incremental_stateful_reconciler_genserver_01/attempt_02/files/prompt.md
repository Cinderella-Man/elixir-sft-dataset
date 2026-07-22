Write me an Elixir module called `Reconciler` that reconciles two sides of records — a "left" side and a "right" side — but instead of a single pure function it must be an **incremental, stateful `GenServer`**: records are fed in one at a time as they arrive, and the reconciliation is computed on demand over whatever has been accumulated so far.

I need this public API:

- `Reconciler.start_link(opts)` — starts the server and returns `{:ok, pid}`. `opts` is a keyword list that must support:
  - `:key_fields` (required) — a list of atoms forming the composite key used to match records across the two sides (e.g., `[:id]` or `[:org_id, :user_id]`). If it is missing, `start_link/1` must raise.
  - `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields except the key fields are compared.

- `Reconciler.put_left(server, record)` — adds a record (a map) to the left side. Returns `:ok`. If a record with the same composite key was already put on the left side, this **replaces** it (last write wins).

- `Reconciler.put_right(server, record)` — the same, for the right side. Returns `:ok`.

- `Reconciler.reconcile(server)` — computes and returns a map with three keys, reflecting the current accumulated state:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for composite keys present on both sides. `diff_map` is a map of `%{field => %{left: val, right: val}}` for any compared field whose values differ (using `==`), and is `%{}` when the records are identical on all compared fields.
  - `:only_in_left` — a list of records whose key is present only on the left side.
  - `:only_in_right` — a list of records whose key is present only on the right side.

- `Reconciler.reset(server)` — clears both sides (left and right become empty). Returns `:ok`. After a reset, `reconcile/1` returns `%{matched: [], only_in_left: [], only_in_right: []}`.

Behaviour requirements:

- Key matching is exact — records match if and only if all key fields have equal values. Composite keys (`[:org_id, :user_id]`) must only match when every key field is equal.
- Matched entries must include both the original left and right record in full, even if some fields are excluded from comparison.
- If a compared field is missing from one or both records, treat the missing value as `nil` and diff accordingly.
- Field comparison is value-exact (using `==`).
- Order of results does not matter.
- `reconcile/1` must not consume or clear state — it can be called repeatedly and reflects all `put_left`/`put_right` calls made so far.

Give me the complete module in a single file.