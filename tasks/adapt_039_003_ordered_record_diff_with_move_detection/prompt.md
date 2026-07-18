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
defmodule RecordDiff do
  @moduledoc """
  Compares two versions of a record list keyed by a unique ID field and
  produces a structured diff describing what was added, removed, or changed.

  ## Example

      iex> old = [%{id: 1, name: "Alice", age: 30}, %{id: 2, name: "Bob", age: 25}]
      iex> new = [%{id: 1, name: "Alice", age: 31}, %{id: 3, name: "Carol", age: 28}]
      iex> RecordDiff.diff(old, new)
      %{
        added:   [%{id: 3, name: "Carol", age: 28}],
        removed: [%{id: 2, name: "Bob",   age: 25}],
        changed: [%{id: 1, changes: %{age: {30, 31}}}]
      }
  """

  @type record_t :: map()
  @type key_value :: term()
  @type field_diff :: {old_value :: term(), new_value :: term()}

  @type change_entry :: %{
          required(atom()) => key_value(),
          required(:changes) => %{atom() => field_diff()}
        }

  @type diff_result :: %{
          added: [record_t()],
          removed: [record_t()],
          changed: [change_entry()]
        }

  @doc """
  Compares `old_list` and `new_list` (both lists of maps) and returns a
  structured diff map.

  ## Options

    * `:key` — the atom key used as the unique record identifier.
      Defaults to `:id`.

  ## Return value

  A map with the following keys:

    * `:added`   — records present in `new_list` but absent in `old_list`.
    * `:removed` — records present in `old_list` but absent in `new_list`.
    * `:changed` — one entry per record that exists in both lists but differs.
      Each entry is a map containing the key field's value and a `:changes`
      sub-map of `%{field => {old_value, new_value}}`.

  Fields that appear in only one version of a record are still reported as
  changes, using the atom `:missing` as a placeholder for the absent value.
  """
  @spec diff([record_t()], [record_t()], keyword()) :: diff_result()
  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)

    old_keys = MapSet.new(Map.keys(old_index))
    new_keys = MapSet.new(Map.keys(new_index))

    added = new_keys |> MapSet.difference(old_keys) |> map_set_to_records(new_index)
    removed = old_keys |> MapSet.difference(new_keys) |> map_set_to_records(old_index)

    changed =
      old_keys
      |> MapSet.intersection(new_keys)
      |> changed_entries(old_index, new_index, key)

    %{added: added, removed: removed, changed: changed}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Build a %{key_value => record} lookup map from a list of records.
  @spec index_by([record_t()], atom()) :: %{term() => record_t()}
  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  # Convert a MapSet of key values to the corresponding list of records,
  # preserving insertion order by sorting keys for determinism.
  @spec map_set_to_records(MapSet.t(), %{term() => record_t()}) :: [record_t()]
  defp map_set_to_records(key_set, index) do
    key_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(index, &1))
  end

  # For every key present in both old and new, compute a change entry if the
  # records differ. Records that are identical are silently dropped.
  @spec changed_entries(MapSet.t(), map(), map(), atom()) :: [change_entry()]
  defp changed_entries(common_keys, old_index, new_index, key) do
    common_keys
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.reduce([], fn key_value, acc ->
      old_record = Map.fetch!(old_index, key_value)
      new_record = Map.fetch!(new_index, key_value)

      case diff_records(old_record, new_record) do
        changes when map_size(changes) == 0 ->
          # Records are identical; nothing to report.
          acc

        changes ->
          entry = %{key => key_value, changes: changes}
          [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  # Compare two versions of the same record field by field.
  # Returns %{field => {old_value, new_value}} for every differing field.
  # Fields present in only one version use :missing as the absent-side value.
  @spec diff_records(record_t(), record_t()) :: %{atom() => field_diff()}
  defp diff_records(old_record, new_record) do
    all_fields =
      (Map.keys(old_record) ++ Map.keys(new_record))
      |> Enum.uniq()

    Enum.reduce(all_fields, %{}, fn field, acc ->
      old_value = Map.get(old_record, field, :missing)
      new_value = Map.get(new_record, field, :missing)

      if old_value == new_value do
        acc
      else
        Map.put(acc, field, {old_value, new_value})
      end
    end)
  end
end
```

## New specification

Write me an Elixir module called `OrderedRecordDiff` that compares two versions of a record list keyed by ID and produces a structured diff that is **order-aware**: the lists are treated as ordered sequences, so besides additions, removals, and field-level changes, the diff must also detect records that were **moved** to a different position.

I need these functions in the public API:
- `OrderedRecordDiff.diff(old_list, new_list, opts \\ [])` where both lists are lists of maps. It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with four keys:
  - `:added` — whole records present in `new_list` but not in `old_list`, in `new_list` order
  - `:removed` — whole records present in `old_list` but not in `new_list`, in `old_list` order
  - `:changed` — one entry per record present in both lists whose fields differ, in `new_list` order. Each entry is `%{key => id, changes: %{field => {old_value, new_value}}}` (fields present in only one version use `:missing` as the absent-side value, exactly as in the base task). Only fields whose values differ between the two versions appear in `changes`; a record whose fields are all equal is omitted from `:changed` entirely.
  - `:moved` — one entry per record whose relative order changed, in `new_list` order. Each entry is `%{key => id, from: old_index, to: new_index}` where the indices are the record's absolute 0-based positions in `old_list` and `new_list`

Move-detection rules:
- Consider only the records that exist in BOTH lists. Take their id sequence in old order and in new order and compute a Longest Common Subsequence (LCS) of the two. The ids that belong to the LCS are the "stable" anchors; every other common id is reported as moved. When the LCS is ambiguous (several are equally long), prefer, at each step, the match that keeps the later element of the new sequence (i.e. when the "skip in new" and "skip in old" branches tie in length, keep the "skip in new" branch).
- A record can appear in BOTH `:changed` and `:moved` if it was reordered and its fields also changed — the two are independent.
- Field-level changes are computed for every common record regardless of whether it moved.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.
