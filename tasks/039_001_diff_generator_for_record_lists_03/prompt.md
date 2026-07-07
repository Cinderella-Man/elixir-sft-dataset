Implement the private `changed_entries/4` function.

It receives four arguments: `common_keys` (a `MapSet` of the key values that are
present in **both** the old and new record lists), `old_index` and `new_index`
(the `%{key_value => record}` lookup maps for the old and new versions
respectively), and `key` (the atom field name used as the unique identifier).

It must produce the list of `:changed` entries — one entry per key whose old and
new records actually differ. For deterministic output, iterate over the common
keys in sorted order. For each key value, fetch the corresponding old and new
records from `old_index`/`new_index` and compute their field-level differences
using the existing `diff_records/2` helper (which returns a
`%{field => {old_value, new_value}}` map). If that map is empty the two records
are identical and must be skipped entirely. Otherwise build a change entry that
is a map containing the key field (`key => key_value`) together with a
`:changes` key holding the differences map, e.g. `%{id: 1, changes: %{age: {30, 31}}}`.

The returned list must preserve sorted-by-key order and contain no entries for
unchanged records.

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

    added   = new_keys |> MapSet.difference(old_keys) |> map_set_to_records(new_index)
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
    # TODO
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