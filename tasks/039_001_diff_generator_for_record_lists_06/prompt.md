# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `map_set_to_records`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Design Brief: `RecordDiff`

## Problem & Constraints

We need to compare two versions of a record list — each keyed by an ID — and produce a structured diff. Build an Elixir module called `RecordDiff` that does this.

Constraints on the implementation:

- Both inputs are lists of maps.
- A record counts as modified only if at least one field actually differs; records that are identical in both lists must not appear in `:changed`.
- Fields must be compared across both versions of a record. If a field is added or removed between old and new versions of the same record, treat it as a change: the old value is `:missing` if the field didn't exist before, and the new value is `:missing` if it was removed.
- The function must be pure — no processes, no state, no side effects.
- Use only the Elixir standard library.
- Deliver the complete module in a single file.

## Required Interface

The public API must provide the following:

1. `RecordDiff.diff(old_list, new_list, opts \\ [])`, where both lists are lists of maps.
2. It must accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`).
3. It must return a map with three keys:
   1. `:added` — a list of records present in `new_list` but not in `old_list`.
   2. `:removed` — a list of records present in `old_list` but not in `new_list`.
   3. `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`), and a `:changes` map where each key is a changed field name and the value is a two-element tuple `{old_value, new_value}`.

## Acceptance Criteria

- Identical records are excluded from `:changed`; a record appears there only when at least one field differs.
- Added or removed fields on the same record are reported as changes, using `:missing` for the absent side (old value `:missing` when newly added, new value `:missing` when removed).
- When both lists are empty, the diff is `%{added: [], removed: [], changed: []}`.
- The function is pure: no processes, no state, no side effects, standard library only.

## The module with `map_set_to_records` missing

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

  defp map_set_to_records(key_set, index) do
    # TODO
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

Output only `map_set_to_records` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
