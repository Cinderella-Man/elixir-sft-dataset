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

  @type record :: map()
  @type key_value :: term()
  @type field_diff :: {old_value :: term(), new_value :: term()}

  @type change_entry :: %{
          required(atom()) => key_value(),
          required(:changes) => %{atom() => field_diff()}
        }

  @type diff_result :: %{
          added: [record()],
          removed: [record()],
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
  @spec diff([record()], [record()], keyword()) :: diff_result()
  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)

    old_keys = MapSet.new(Map.keys(old_index))
    new_keys = MapSet.new(Map.keys(new_index))

    added   = new_keys |> MapSet.difference(old_keys) |> map_set_to_records(new_index)
    removed = old_keys |> MapSet.difference(new_keys) |> map_set_to_records(old_index)
    changed = old_keys |> MapSet.intersection(new_keys) |> changed_entries(old_index, new_index, key)

    %{added: added, removed: removed, changed: changed}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Build a %{key_value => record} lookup map from a list of records.
  @spec index_by([record()], atom()) :: %{term() => record()}
  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  # Convert a MapSet of key values to the corresponding list of records,
  # preserving insertion order by sorting keys for determinism.
  @spec map_set_to_records(MapSet.t(), %{term() => record()}) :: [record()]
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
  @spec diff_records(record(), record()) :: %{atom() => field_diff()}
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
