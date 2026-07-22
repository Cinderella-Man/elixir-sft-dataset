Write me an Elixir module called `StreamReconciler` — a GenServer that reconciles two record streams **incrementally**, as records arrive, instead of taking two complete lists up front.

Records from the two sides (`left` and `right`) are pushed in one at a time, in any interleaving. The server buffers records that have not yet found a partner; the moment a record whose key is already pending on the *other* side arrives, the two are matched, removed from the buffers, and the resulting matched entry is queued for the caller to collect.

I need these functions in the public API:

- `StreamReconciler.start_link(opts)` — starts the server, returns `{:ok, pid}`. `opts` is a keyword list supporting:
  - `:key_fields` (required) — a non-empty list of atoms forming the composite key (e.g. `[:id]` or `[:org_id, :user_id]`).
  - `:compare_fields` (optional) — a list of atoms to diff on matched records. If omitted or `nil`, compare every field present in either record of the matched pair except the key fields.
  - `:name` (optional) — a name to register the process under; when given, every other function must also accept that name in place of a pid.
- `StreamReconciler.push_left(server, record)` — pushes one map onto the left side. Returns `:ok`.
- `StreamReconciler.push_right(server, record)` — pushes one map onto the right side. Returns `:ok`.
- `StreamReconciler.take_matches(server)` — returns the list of matched entries produced since the last `take_matches/1` call (or since start), **in the order the matches completed**, and clears that queue. Calling it again immediately returns `[]`.
- `StreamReconciler.pending_counts(server)` — returns `%{left: n, right: m}`, the number of records currently buffered on each side awaiting a partner.
- `StreamReconciler.finalize(server)` — returns `%{matched: [...], only_in_left: [...], only_in_right: [...]}` where `matched` holds the matched entries not yet collected by `take_matches/1`, `only_in_left` holds the left records still buffered (the raw maps), and `only_in_right` the right ones. After replying, the server **stops with reason `:normal`**.
- `StreamReconciler.stop(server)` — stops the server without producing a result.

A **matched entry** is `%{key: key_map, left: record, right: record, differences: diff_map}` where:

- `key_map` is `%{field => value}` over the key fields, e.g. `%{id: 1}` or `%{org_id: 1, user_id: 10}`.
- `diff_map` is `%{field => %{left: left_value, right: right_value}}`, holding an entry only for compared fields whose values differ. It is `%{}` when the records agree on every compared field.

Behaviour requirements:

- Key matching is exact — two records match if and only if all key fields have equal (`==`) values. Composite keys must only match when *all* key fields agree.
- Matching happens on push: pushing a record whose key is pending on the opposite side immediately produces a matched entry and removes both records from the buffers. Which side arrives first must not matter.
- The matched entry always stores the left-side record under `:left` and the right-side record under `:right`, regardless of arrival order.
- Field comparison is value-exact (`==`). A compared field missing from one or both records is treated as `nil` and diffed accordingly.
- **Same-side duplicate keys: last write wins.** If a record is pushed whose key is already pending on the *same* side, the newly pushed record replaces the buffered one (the older record is dropped and never reported). The pending count for that side is unchanged.
- A key field missing from a record contributes `nil` to its key map.
- The order of `:only_in_left` and `:only_in_right` in the `finalize/1` result does not matter.
- Use only the Elixir/Erlang standard library — no external dependencies.

Give me the complete module in a single file.