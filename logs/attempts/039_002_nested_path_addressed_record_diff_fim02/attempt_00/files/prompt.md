Implement the public `diff/3` function.

It is the single entry point of `NestedRecordDiff`. Given `old_list` and
`new_list` (both lists of maps whose values may themselves be nested maps) plus
an `opts` keyword list, it must compute a structured diff keyed by a unique
identifier field.

Details:

- Read the identifier field from `opts` under `:key`, defaulting to `:id`. Use
  `Keyword.get/3`.
- Build an index of each list keyed by that field using the `index_by/2` helper,
  producing `old_index` and `new_index`.
- Derive the set of keys present in each index (a `MapSet` of the map keys of
  `old_index` and of `new_index`).
- Compute `:added` as the records whose keys are in `new_keys` but not
  `old_keys`, and `:removed` as the records whose keys are in `old_keys` but not
  `new_keys`. In both cases turn the resulting key set back into whole records
  with the `to_records/2` helper.
- Compute `:changed` from the keys present in BOTH indexes: sort them, and for
  each shared key run `deep_changes/2` on the old and new record. Skip records
  whose changes map is empty (`map_size/1` of `0`); for the rest, accumulate an
  entry shaped `%{key => shared_key_value, changes: changes}`. Preserve ascending
  key order in the final `:changed` list.
- Return `%{added: added, removed: removed, changed: changed}`.

The function must be pure — no processes, no state, no side effects — and use
only the Elixir standard library.

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
    # TODO
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