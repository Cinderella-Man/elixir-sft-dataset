Implement the private `join/2` helper for `NestedRecordDiff`.

`join/2` builds a dotted path string for a nested field. It receives the current
`prefix` (a string that is `""` at the top level, or an already-built dotted path
like `"address"` deeper in the recursion) and a `field` (an atom field name). When
the `prefix` is empty (`""`), it must return just the field name as a string (no
leading dot). Otherwise it must return the `prefix`, a `"."` separator, and the
field name joined together (e.g. `join("address", :city)` yields `"address.city"`).
In both cases the atom `field` is converted to a string with `to_string/1`.

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

        true ->
          Map.put(acc, path, {old_value, new_value})
      end
    end)
  end

  defp join(prefix, field) do
    # TODO
  end
end
```