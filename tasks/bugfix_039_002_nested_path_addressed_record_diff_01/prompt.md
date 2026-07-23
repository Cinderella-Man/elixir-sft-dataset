# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Hey — could you write me an Elixir module called `NestedRecordDiff`? I need it to compare two versions of a record list keyed by ID and produce a structured diff, but here's the twist: unlike a shallow field-by-field diff, this one has to descend into nested maps and report every change addressed by a dotted path.

For the public API, I'm after these functions:

I want `NestedRecordDiff.diff(old_list, new_list, opts \\ [])`, where both lists are lists of maps (and those maps' values may themselves be maps, nested to arbitrary depth). It should accept a `:key` option — an atom specifying which field to use as the unique identifier — defaulting to `:id`. It should return a map with three keys:
- `:added` — a list of whole records present in `new_list` but not in `old_list`
- `:removed` — a list of whole records present in `old_list` but not in `new_list`
- `:changed` — a list of maps, one per modified record, each containing: the key field's value (e.g. `id: 1`) and a `:changes` map where each key is a dotted path string (e.g. `"address.city"`) locating a changed leaf, and each value is a two-element tuple `{old_value, new_value}`

A few rules I care about for the paths:
- Recurse into a field only when the value is a map in BOTH versions of the record. Two nested maps get compared key-by-key, and their dotted paths are built by joining the atom field names with `"."` (so `%{address: %{city: ...}}` yields paths like `"address.city"`).
- If a field is a map on one side and a scalar (or missing) on the other, do NOT recurse — just report the whole value change at that field's path (e.g. `"address" => {%{...}, "unknown"}`).
- If a leaf field is added or removed between the old and new versions of the same record, treat it as a change: use the atom `:missing` for the absent side (`{:missing, new}` for an added leaf, `{old, :missing}` for a removed one).
- Only report a `:changed` entry for a record whose comparison yields at least one path.

One more thing — the function has to be pure: no processes, no state, no side effects. Please stick to the Elixir standard library only.

Send me the complete module in a single file.

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

        if map_size(changes) == 0 do
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

        false ->
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

  * test nested leaf change is reported with a dotted path
      no cond clause evaluated to a truthy value

  * test top-level and nested changes coexist
      no cond clause evaluated to a truthy value

  * test deeply nested leaf change builds a multi-segment path
      no cond clause evaluated to a truthy value

  * test nested leaf added inside an existing map uses :missing old value
      no cond clause evaluated to a truthy value

  (…5 more)
```
