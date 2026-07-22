Write me an Elixir module called `StreamReconciler` — a GenServer that reconciles two record streams **incrementally**, as records arrive one at a time from either side, instead of taking two complete lists.

The idea: records from the left feed and the right feed trickle in interleaved and out of order. Each unmatched record is parked as *pending* until its counterpart shows up on the other side; when a pair completes, a matched entry is produced immediately and also buffered for later collection.

## Public API

- `StreamReconciler.start_link(opts)` — starts the server, returns `{:ok, pid}`.
- `StreamReconciler.push_left(server, record)` — feeds one map from the left stream.
- `StreamReconciler.push_right(server, record)` — feeds one map from the right stream.
- `StreamReconciler.take_matches(server)` — drains and returns the buffered matched entries.
- `StreamReconciler.pending(server)` — returns the records still waiting for a counterpart.
- `StreamReconciler.stop(server)` — stops the server, returns `:ok`.

`server` is a pid (or a registered name if `:name` was given).

## Options for start_link/1

- `:key_fields` (required) — a non-empty list of atoms forming the composite key. If it is missing, or is not a non-empty list of atoms, raise `ArgumentError`.
- `:compare_fields` (optional) — a list of atoms to diff on a completed pair. If omitted or `nil`, compare every field present in either record of the pair, minus the key fields.
- `:name` (optional) — a name to register the server under, passed through to `GenServer`.

## Push semantics

A record's composite key is the tuple of its values at the key fields, in order; a key field missing from the record contributes `nil`.

`push_left(server, record)`:

- If a **pending right** record with the same key exists, it is removed from pending, the pair is completed, and the call returns `{:matched, entry}`.
- Otherwise the record is parked as pending-left and the call returns `:pending`. If a pending-left record with the same key already exists, the **new record replaces it** (last write wins).

`push_right/2` is exactly symmetric (it looks for a pending **left** record, and parks under pending-right otherwise).

A completed pair produces:

    %{key: key_map, left: left_record, right: right_record, differences: diff_map}

- `key_map` is `%{key_field => value}` for the pair's key.
- `left` / `right` are always the full original records from their respective sides, regardless of which push completed the pair.
- `diff_map` is `%{field => %{left: left_value, right: right_value}}` for each compared field whose values differ under `==`, and `%{}` when the pair agrees on all compared fields. A compared field missing from a record is treated as `nil`.

Every entry returned by a push is **also appended to an internal match buffer**.

## take_matches/1

Returns the buffered matched entries **in the order their pairs were completed**, and empties the buffer — so an immediately following `take_matches/1` returns `[]`.

## pending/1

Returns `%{left: [records], right: [records]}` — the records currently parked on each side awaiting a counterpart, as full original maps. The order within each list is unspecified. Calling `pending/1` does not change any state.

## Constraints

- Use OTP: `GenServer` only, no ETS, no external dependencies.
- All calls must be synchronous enough that a push's effect is visible to a subsequent `take_matches/1` or `pending/1` from the same caller.

Give me the complete module in a single file.