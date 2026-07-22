Write me an Elixir module called `StreamingReconciler`, implemented as a **GenServer**, that reconciles two streams of records incrementally. Instead of receiving both complete lists up front, records arrive one at a time tagged as coming from the left side or the right side, and the current reconciliation can be queried at any point.

I need this public API:

- `StreamingReconciler.start_link(opts)` — starts the server. `opts` is a keyword list supporting:
  - `:key_fields` (required) — a list of atoms forming the composite key used to match a left record against a right record. Two records match if and only if all key fields are equal.
  - `:compare_fields` (optional) — a list of atoms specifying which fields to diff on matched records. If omitted or `nil`, all fields present in either matched record except the key fields are compared.

  It returns `{:ok, pid}`.

- `StreamingReconciler.add_left(pid, record)` — ingest one record into the left side. Returns `:ok`.
- `StreamingReconciler.add_right(pid, record)` — ingest one record into the right side. Returns `:ok`.
- `StreamingReconciler.snapshot(pid)` — returns the current reconciliation as a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}` entries for keys present on both sides, where `diff_map` is `%{field => %{left: val, right: val}}` for compared fields whose values differ (using `==`), and is empty when all compared fields are equal.
  - `:only_in_left` — the left records whose key has not (yet) been seen on the right side.
  - `:only_in_right` — the right records whose key has not (yet) been seen on the left side.
- `StreamingReconciler.reset(pid)` — discards all ingested records on both sides, returning the server to an empty state. Returns `:ok`.

Behaviour requirements:
- Reconciliation is computed against whatever has been ingested so far. A key that is only-in-left in one snapshot becomes matched once a right record with the same key is added later.
- Within a side, if the same key is ingested more than once, the most recently added record wins for that side.
- Key matching must be exact and support composite keys (`[:org_id, :user_id]` matches only when both fields are equal).
- If a compared field is missing from one of a matched pair, treat the missing value as `nil` and diff accordingly.
- Matched entries must include both full original records.
- Order of the lists in a snapshot does not matter.
- Use only the Elixir/OTP standard library.

Give me the complete module in a single file.