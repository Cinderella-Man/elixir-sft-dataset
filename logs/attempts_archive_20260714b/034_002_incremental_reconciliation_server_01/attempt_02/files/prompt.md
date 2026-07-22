# Incremental Reconciliation Server

Write me an Elixir module called `ReconcilerServer`. It is a `GenServer` that
accumulates records from two sides — a "left" side and a "right" side — as they
arrive over time, and reconciles the *current* accumulated state on demand,
producing a structured diff by a shared composite key.

Unlike a one-shot reconciler, records are fed in incrementally and the server
keeps state between calls.

## Public API

- `ReconcilerServer.start_link(opts)` — starts the server. `opts` is a keyword
  list that must support:
  - `:key_fields` (required) — a list of atoms that together form the composite
    key used to match records across the two sides (e.g. `[:id]` or
    `[:org_id, :user_id]`). It must be a non-empty list of atoms; otherwise
    `start_link/1` raises `ArgumentError`.
  - `:compare_fields` (optional) — a list of atoms specifying which fields to
    diff on matched records. If omitted or `nil`, all fields except the key
    fields are compared.
  - `:name` (optional) — if given, the server is registered under this name
    (passed through to `GenServer`).

  Returns `{:ok, pid}`.

- `ReconcilerServer.put_left(server, record)` — stores `record` (a map) on the
  left side. If a left record with the same composite key already exists, it is
  replaced (last write wins). Returns `:ok`.

- `ReconcilerServer.put_right(server, record)` — same, for the right side.
  Returns `:ok`.

- `ReconcilerServer.delete_left(server, record)` — removes the left record whose
  composite key matches that of `record` (only the key fields of `record` are
  used to locate it). If no such record exists, it is a no-op. Returns `:ok`.

- `ReconcilerServer.delete_right(server, record)` — same, for the right side.
  Returns `:ok`.

- `ReconcilerServer.reconcile(server)` — computes and returns the reconciliation
  of the *current* accumulated state as a map with three keys:
  - `:matched` — a list of `%{left: record, right: record, differences: diff_map}`
    entries for composite keys present on both sides. `diff_map` is a map of
    `%{field => %{left: val, right: val}}` for any compared field whose values
    differ, and is empty (`%{}`) if the records are equal on all compared fields.
  - `:only_in_left` — records whose composite key is present only on the left side.
  - `:only_in_right` — records whose composite key is present only on the right side.

## Behaviour requirements

- Key matching must be exact. Two records match if and only if all key fields
  have equal values. Composite keys must work correctly — `[:org_id, :user_id]`
  matches only when both fields are equal.
- Field comparison must be value-exact (using `==`).
- Matched entries must include both the original left and right record in full,
  even if some fields are excluded from comparison.
- If a compared field is missing from one or both records, treat the missing
  value as `nil` and diff accordingly.
- Each call to `reconcile/1` reflects the state at that moment. Adding, replacing
  or deleting records between calls changes subsequent results.
- Order of results does not matter.
- Use only the Elixir/OTP standard library.

Give me the complete module in a single file.