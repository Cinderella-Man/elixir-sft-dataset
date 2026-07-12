# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `NestedRecordDiff` that compares two versions of a record list keyed by ID and produces a structured diff — but unlike a shallow field-by-field diff, this one must descend into **nested maps** and report every change addressed by a dotted path.

I need these functions in the public API:
- `NestedRecordDiff.diff(old_list, new_list, opts \\ [])` where both lists are lists of maps (whose values may themselves be maps, nested to arbitrary depth). It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with three keys:
  - `:added` — a list of whole records present in `new_list` but not in `old_list`
  - `:removed` — a list of whole records present in `old_list` but not in `new_list`
  - `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`) and a `:changes` map where each key is a **dotted path string** (e.g. `"address.city"`) locating a changed leaf, and each value is a two-element tuple `{old_value, new_value}`

Path rules:
- Recurse into a field only when the value is a map in BOTH versions of the record. Two nested maps are compared key-by-key, and their dotted paths are built by joining the atom field names with `"."` (so `%{address: %{city: ...}}` yields paths like `"address.city"`).
- If a field is a map on one side and a scalar (or missing) on the other, do NOT recurse — report the whole value change at that field's path (e.g. `"address" => {%{...}, "unknown"}`).
- If a leaf field is added or removed between old and new versions of the same record, treat it as a change: use the atom `:missing` for the absent side (`{:missing, new}` for an added leaf, `{old, :missing}` for a removed one).
- Only report a `:changed` entry for a record whose comparison yields at least one path.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.

## The buggy module

```elixir
defmodule NestedRecordDiff do
  @moduledoc """
  Compares two versions of a record list keyed by a unique ID field and
  produces a structured diff. Unlike a shallow diff, nested maps are compared
  recursively and every change is addressed by a dotted path string
  (e.g. `"address.city"`).
  """

  @doc """
  Compares `old_list` and `new_list` (both lists of possibly-nested maps) and
  returns `%{added: [...], removed: [...], changed: [...]}`.

  Options:

    * `:key` — atom used as the unique record identifier (defaults to `:id`).

  Each `:changed` entry is `%{key => id, changes: %{path_string => {old, new}}}`.
  """
  @spec diff([map()], [map()], keyword()) :: %{
          added: [map()],
          removed: [map()],
          changed: [map()]
        }
  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)

    old_keys = old_index |> Map.keys() |> MapSet.new()
    new_keys = new_index |> Map.keys() |> MapSet.new()

    added = new_keys |> MapSet.difference(old_keys) |> to_records(new_index)
    removed = old_keys |> MapSet.difference(new_keys) |> to_records(old_index)

    changed =
      old_keys
      |> MapSet.intersection(new_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce([], fn kv, acc ->
        changes = deep_changes(Map.fetch!(old_index, kv), Map.fetch!(new_index, kv))

        if map_size(changes) == 1 do
          acc
        else
          [%{key => kv, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    %{added: added, removed: removed, changed: changed}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  defp to_records(key_set, index) do
    key_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(index, &1))
  end

  defp deep_changes(old_map, new_map) do
    deep_changes(old_map, new_map, "", %{})
  end

  defp deep_changes(old_map, new_map, prefix, acc) do
    fields =
      (Map.keys(old_map) ++ Map.keys(new_map))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(fields, acc, fn field, acc ->
      path = join(prefix, field)
      old_value = Map.get(old_map, field, :missing)
      new_value = Map.get(new_map, field, :missing)

      cond do
        is_map(old_value) and is_map(new_value) ->
          deep_changes(old_value, new_value, path, acc)

        old_value == new_value ->
          acc

        true ->
          Map.put(acc, path, {old_value, new_value})
      end
    end)
  end

  defp join("", field), do: to_string(field)
  defp join(prefix, field), do: prefix <> "." <> to_string(field)
end
```

## Failing test report

```
9 of 12 test(s) failed:

  * test identical nested lists produce an empty diff
      
      
      Assertion with == failed
      code:  assert NestedRecordDiff.diff(records, records) == %{added: [], removed: [], changed: []}
      left:  %{removed: [], added: [], changed: [%{id: 1, changes: %{}}]}
      right: %{removed: [], added: [], changed: []}
      

  * test nested leaf change is reported with a dotted path
      expected a map, got:
      
          nil
      

  * test deeply nested leaf change builds a multi-segment path
      expected a map, got:
      
          nil
      

  * test nested leaf added inside an existing map uses :missing old value
      expected a map, got:
      
          nil
      

  (…5 more)
```
