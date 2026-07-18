# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule RecordDiff do
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
  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  # Convert a MapSet of key values to the corresponding list of records,
  # preserving insertion order by sorting keys for determinism.
  defp map_set_to_records(key_set, index) do
    key_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(index, &1))
  end

  # For every key present in both old and new, compute a change entry if the
  # records differ. Records that are identical are silently dropped.
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
