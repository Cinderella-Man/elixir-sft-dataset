Implement the private `deep_changes/4` function.

It is the recursive worker behind `deep_changes/2` and accumulates the dotted-path
changes between two (possibly nested) record maps. It receives four arguments:
`old_map`, `new_map`, `prefix` (the dotted-path string accumulated so far — `""`
at the top level), and `acc` (the map of `path_string => {old, new}` built up so
far).

It must:

  * Build the set of fields to inspect from the **union** of `old_map`'s and
    `new_map`'s keys, de-duplicated and sorted so output is deterministic.
  * Reduce over those fields, threading `acc`. For each `field`:
    * Compute its full `path` by combining `prefix` and `field` with `join/2`.
    * Look up `old_value` and `new_value`, using the atom `:missing` as the default
      when the field is absent on that side.
    * If **both** values are maps, recurse with `deep_changes/4` (passing `path`
      as the new prefix and the current `acc`) so nested changes are addressed by
      their dotted paths.
    * Otherwise, if the two values are equal, leave `acc` unchanged.
    * Otherwise, record the change by putting `{old_value, new_value}` under `path`
      in `acc`.
  * Return the final accumulator map.

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
    # TODO
  end

  defp join("", field), do: to_string(field)
  defp join(prefix, field), do: prefix <> "." <> to_string(field)
end
```