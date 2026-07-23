# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule Reconciler do
  @moduledoc """
  Reconciles two lists of records by a composite key, producing a structured diff.

  ## Example

      left  = [%{id: 1, name: "Alice", age: 30}, %{id: 2, name: "Bob", age: 25}]
      right = [%{id: 1, name: "Alice", age: 31}, %{id: 3, name: "Carol", age: 28}]

      Reconciler.reconcile(left, right, key_fields: [:id])
      #=> %{
      #=>   matched: [
      #=>     %{
      #=>       left: %{id: 1, name: "Alice", age: 30},
      #=>       right: %{id: 1, name: "Alice", age: 31},
      #=>       differences: %{age: %{left: 30, right: 31}}
      #=>     }
      #=>   ],
      #=>   only_in_left:  [%{id: 2, name: "Bob",   age: 25}],
      #=>   only_in_right: [%{id: 3, name: "Carol",  age: 28}]
      #=> }
  """

  @type record_t :: map()
  @type diff_map :: %{optional(atom()) => %{left: term(), right: term()}}

  @type matched_entry :: %{
          left: record_t(),
          right: record_t(),
          differences: diff_map()
        }

  @type result :: %{
          matched: [matched_entry()],
          only_in_left: [record_t()],
          only_in_right: [record_t()]
        }

  @doc """
  Reconciles `left` and `right` lists of maps by the composite key defined in `opts`.

  ## Options

    * `:key_fields` (required) — list of atoms forming the composite match key,
      e.g. `[:id]` or `[:org_id, :user_id]`.

    * `:compare_fields` (optional) — list of atoms to diff on matched pairs.
      Defaults to all fields present in either record, minus the key fields.

  ## Return value

  A map with three keys:

    * `:matched`       — pairs found in both lists, each with a `differences` map.
    * `:only_in_left`  — records found only in `left`.
    * `:only_in_right` — records found only in `right`.
  """
  @spec reconcile([record_t()], [record_t()], keyword()) :: result()
  def reconcile(left, right, opts) when is_list(left) and is_list(right) and is_list(opts) do
    key_fields = fetch_key_fields!(opts)
    compare_fields_opt = Keyword.get(opts, :compare_fields, nil)

    # Index both sides by composite key — last write wins for duplicate keys,
    # consistent with a pure functional, side-effect-free contract.
    left_index = index_by(left, key_fields)
    right_index = index_by(right, key_fields)

    left_keys = MapSet.new(Map.keys(left_index))
    right_keys = MapSet.new(Map.keys(right_index))

    matched_keys = MapSet.intersection(left_keys, right_keys)
    only_left_keys = MapSet.difference(left_keys, right_keys)
    only_right_keys = MapSet.difference(right_keys, left_keys)

    matched =
      matched_keys
      |> Enum.map(fn key ->
        l = Map.fetch!(left_index, key)
        r = Map.fetch!(right_index, key)
        fields = resolve_compare_fields(l, r, key_fields, compare_fields_opt)
        %{left: l, right: r, differences: diff(l, r, fields)}
      end)

    only_in_left = Enum.map(only_left_keys, &Map.fetch!(left_index, &1))
    only_in_right = Enum.map(only_right_keys, &Map.fetch!(right_index, &1))

    %{matched: matched, only_in_left: only_in_left, only_in_right: only_in_right}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Validates and returns :key_fields from opts, raising on bad input.
  defp fetch_key_fields!(opts) do
    case Keyword.fetch(opts, :key_fields) do
      {:ok, fields} when is_list(fields) and fields != [] ->
        unless Enum.all?(fields, &is_atom/1) do
          raise ArgumentError, ":key_fields must be a non-empty list of atoms"
        end

        fields

      {:ok, _} ->
        raise ArgumentError, ":key_fields must be a non-empty list of atoms"

      :error ->
        raise ArgumentError, "required option :key_fields is missing"
    end
  end

  # Builds a map of composite_key => record for fast O(1) lookups.
  # The composite key is a tuple of the values at the key fields in order,
  # e.g. {org_id_val, user_id_val}.  A single-field key uses a 1-tuple so
  # the representation is uniform and avoids collisions with plain values.
  @spec index_by([record_t()], [atom()]) :: %{tuple() => record_t()}
  defp index_by(records, key_fields) do
    Map.new(records, fn record ->
      {composite_key(record, key_fields), record}
    end)
  end

  @spec composite_key(record_t(), [atom()]) :: tuple()
  defp composite_key(record, key_fields) do
    key_fields
    |> Enum.map(&Map.get(record, &1))
    |> List.to_tuple()
  end

  # Determines which fields to compare for a matched pair.
  # If compare_fields is explicitly provided, use it directly.
  # Otherwise, derive it as: (all keys in left ∪ right) minus key_fields.
  @spec resolve_compare_fields(record_t(), record_t(), [atom()], [atom()] | nil) :: [atom()]
  defp resolve_compare_fields(_left, _right, _key_fields, compare_fields)
       when is_list(compare_fields),
       do: compare_fields

  defp resolve_compare_fields(left, right, key_fields, nil) do
    all_fields =
      (Map.keys(left) ++ Map.keys(right))
      |> Enum.uniq()

    key_set = MapSet.new(key_fields)
    Enum.reject(all_fields, &MapSet.member?(key_set, &1))
  end

  # Compares `left` and `right` on the given fields using `==`.
  # Missing fields are treated as nil.
  @spec diff(record_t(), record_t(), [atom()]) :: diff_map()
  defp diff(left, right, fields) do
    Enum.reduce(fields, %{}, fn field, acc ->
      lv = Map.get(left, field)
      rv = Map.get(right, field)

      if lv == rv do
        acc
      else
        Map.put(acc, field, %{left: lv, right: rv})
      end
    end)
  end
end
```

## New specification

# StreamReconciler Specification

## Overview

`StreamReconciler` is an Elixir module implemented as a GenServer that reconciles two record streams **incrementally**, processing records as they arrive one at a time from either side, rather than accepting two complete lists.

Records from the left feed and the right feed trickle in interleaved and out of order. Each unmatched record is parked as *pending* until its counterpart appears on the other side. When a pair completes, a matched entry is produced immediately and also buffered for later collection.

The module is to be delivered complete, in a single file.

## API

The public interface consists of the following functions:

- `StreamReconciler.start_link(opts)` — starts the server and returns `{:ok, pid}`.
- `StreamReconciler.push_left(server, record)` — feeds one map from the left stream.
- `StreamReconciler.push_right(server, record)` — feeds one map from the right stream.
- `StreamReconciler.take_matches(server)` — drains and returns the buffered matched entries.
- `StreamReconciler.pending(server)` — returns the records still waiting for a counterpart.
- `StreamReconciler.stop(server)` — stops the server and returns `:ok`.

`server` is a pid (or a registered name if `:name` was given).

### Options for start_link/1

- `:key_fields` (required) — a non-empty list of atoms forming the composite key. If it is missing, or is not a non-empty list of atoms, `ArgumentError` is raised.
- `:compare_fields` (optional) — a list of atoms to diff on a completed pair. If it is omitted or `nil`, every field present in either record of the pair is compared, minus the key fields.
- `:name` (optional) — a name to register the server under, passed through to `GenServer`.

### Push semantics

A record's composite key is the tuple of its values at the key fields, in order; a key field missing from the record contributes `nil`.

`push_left(server, record)` behaves as follows:

- If a **pending right** record with the same key exists, it is removed from pending, the pair is completed, and the call returns `{:matched, entry}`.
- Otherwise the record is parked as pending-left and the call returns `:pending`. If a pending-left record with the same key already exists, the **new record replaces it** (last write wins).

`push_right/2` is exactly symmetric: it looks for a pending **left** record, and parks under pending-right otherwise.

A completed pair produces:

    %{key: key_map, left: left_record, right: right_record, differences: diff_map}

- `key_map` is `%{key_field => value}` for the pair's key.
- `left` / `right` are always the full original records from their respective sides, regardless of which push completed the pair.
- `diff_map` is `%{field => %{left: left_value, right: right_value}}` for each compared field whose values differ under `==`, and `%{}` when the pair agrees on all compared fields. A compared field missing from a record is treated as `nil`.

Every entry returned by a push is **also appended to an internal match buffer**.

### take_matches/1

Returns the buffered matched entries **in the order their pairs were completed**, and empties the buffer — so an immediately following `take_matches/1` returns `[]`.

### pending/1

Returns `%{left: [records], right: [records]}` — the records currently parked on each side awaiting a counterpart, as full original maps. The order within each list is unspecified. Calling `pending/1` does not change any state.

## Edge cases and constraints

- A key field missing from a record contributes `nil` to the composite key.
- When `:compare_fields` is omitted or `nil`, comparison covers every field present in either record of the pair, minus the key fields.
- A compared field missing from a record is treated as `nil`.
- When the pair agrees on all compared fields, `diff_map` is `%{}`.
- `left` and `right` are always the full original records from their respective sides, independent of which push completed the pair.
- Under last-write-wins, a new pending record on a side replaces any existing pending record with the same key on that side.
- Missing or invalid `:key_fields` (not a non-empty list of atoms) raises `ArgumentError`.
- Use OTP: `GenServer` only, no ETS, no external dependencies.
- All calls must be synchronous enough that a push's effect is visible to a subsequent `take_matches/1` or `pending/1` from the same caller.
