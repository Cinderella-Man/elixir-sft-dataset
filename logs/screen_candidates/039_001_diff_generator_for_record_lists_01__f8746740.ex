defmodule RecordDiff do
  @moduledoc """
  Compares two versions of a record list keyed by a unique identifier field and
  produces a structured diff.

  Records are maps. Two records correspond to one another when their key field
  (`:id` by default, configurable via the `:key` option) holds the same value.

  The diff distinguishes three outcomes:

    * `:added` — records whose key appears only in the new list
    * `:removed` — records whose key appears only in the old list
    * `:changed` — records present in both lists whose fields differ

  Field-level changes are reported as `{old_value, new_value}` tuples. Fields
  that appear in only one version of a record are still reported as changes,
  using the `:missing` sentinel for the side where the field is absent.

  All functions in this module are pure: they perform no I/O, spawn no
  processes, and hold no state.

  ## Examples

      iex> old = [%{id: 1, name: "a", size: 10}, %{id: 2, name: "b"}]
      iex> new = [%{id: 1, name: "a", size: 12}, %{id: 3, name: "c"}]
      iex> RecordDiff.diff(old, new)
      %{
        added: [%{id: 3, name: "c"}],
        removed: [%{id: 2, name: "b"}],
        changed: [%{id: 1, changes: %{size: {10, 12}}}]
      }
  """

  @typedoc "A single record: a map with at least the key field present."
  @type record :: map()

  @typedoc "A field-level change: the old value and the new value."
  @type change :: {old :: term(), new :: term()}

  @typedoc "A per-record change entry: the key field plus a `:changes` map."
  @type changed_entry :: %{required(:changes) => %{optional(term()) => change()}}

  @typedoc "The structured diff returned by `diff/3`."
  @type result :: %{
          added: [record()],
          removed: [record()],
          changed: [changed_entry()]
        }

  @missing :missing

  @doc """
  Compares `old_list` against `new_list` and returns a structured diff.

  Both arguments are lists of maps. Records are matched up by the value of their
  key field, which defaults to `:id` and can be changed with the `:key` option.

  Returns a map with:

    * `:added` — records from `new_list` whose key is absent from `old_list`,
      in their original `new_list` order
    * `:removed` — records from `old_list` whose key is absent from `new_list`,
      in their original `old_list` order
    * `:changed` — one map per differing record, containing the key field (for
      example `id: 1`) and a `:changes` map of `field => {old, new}` entries,
      ordered by first appearance in `old_list`

  A field present in both versions is reported only when its values differ
  (compared with strict equality, so `1` and `1.0` count as a change). A field
  present in just one version is reported with `:missing` standing in for the
  absent side. Records lacking the key field entirely are ignored.

  ## Options

    * `:key` — atom naming the field that uniquely identifies a record.
      Defaults to `:id`.

  ## Examples

      iex> RecordDiff.diff([%{id: 1, a: 1}], [%{id: 1, b: 2}])
      %{added: [], removed: [], changed: [%{id: 1, changes: %{a: {1, :missing}, b: {:missing, 2}}}]}

      iex> RecordDiff.diff([%{uuid: "x", n: 1}], [%{uuid: "x", n: 2}], key: :uuid)
      %{added: [], removed: [], changed: [%{uuid: "x", changes: %{n: {1, 2}}}]}

      iex> RecordDiff.diff([%{id: 1, ratio: +0.0}], [%{id: 1, ratio: -0.0}])
      %{added: [], removed: [], changed: [%{id: 1, changes: %{ratio: {+0.0, -0.0}}}]}
  """
  @spec diff([record()], [record()], keyword()) :: result()
  def diff(old_list, new_list, opts \\ []) when is_list(old_list) and is_list(new_list) do
    key = Keyword.get(opts, :key, :id)

    old_indexed = index_by(old_list, key)
    new_indexed = index_by(new_list, key)

    %{
      added: only_in(new_list, new_indexed, old_indexed, key),
      removed: only_in(old_list, old_indexed, new_indexed, key),
      changed: changed_entries(old_list, old_indexed, new_indexed, key)
    }
  end

  # Builds a `key value => record` map, ignoring records without the key field.
  # Later records win on duplicate keys, matching `Map.new/2` semantics.
  @spec index_by([record()], atom()) :: %{optional(term()) => record()}
  defp index_by(list, key) do
    for record <- list, is_map(record), Map.has_key?(record, key), into: %{} do
      {Map.fetch!(record, key), record}
    end
  end

  # Returns the records of `list` whose key is absent from `other_indexed`,
  # preserving `list` order and collapsing duplicate keys to one record.
  @spec only_in([record()], %{optional(term()) => record()}, %{optional(term()) => record()}, atom()) ::
          [record()]
  defp only_in(list, indexed, other_indexed, key) do
    list
    |> distinct_keys(key)
    |> Enum.reject(&Map.has_key?(other_indexed, &1))
    |> Enum.map(&Map.fetch!(indexed, &1))
  end

  # Returns a `:changes` entry for every record present in both versions whose
  # fields differ, ordered by first appearance in the old list.
  @spec changed_entries(
          [record()],
          %{optional(term()) => record()},
          %{optional(term()) => record()},
          atom()
        ) :: [changed_entry()]
  defp changed_entries(old_list, old_indexed, new_indexed, key) do
    old_list
    |> distinct_keys(key)
    |> Enum.flat_map(fn key_value ->
      case Map.fetch(new_indexed, key_value) do
        {:ok, new_record} ->
          old_record = Map.fetch!(old_indexed, key_value)

          case field_changes(old_record, new_record, key) do
            changes when map_size(changes) == 0 -> []
            changes -> [%{key => key_value, :changes => changes}]
          end

        :error ->
          []
      end
    end)
  end

  # Collects the distinct key values of `list`, in order of first appearance.
  @spec distinct_keys([record()], atom()) :: [term()]
  defp distinct_keys(list, key) do
    list
    |> Enum.filter(&(is_map(&1) and Map.has_key?(&1, key)))
    |> Enum.map(&Map.fetch!(&1, key))
    |> Enum.uniq()
  end

  # Compares every field of both records except the key field itself, using
  # `:missing` for fields that exist on only one side.
  @spec field_changes(record(), record(), atom()) :: %{optional(term()) => change()}
  defp field_changes(old_record, new_record, key) do
    old_record
    |> Map.keys()
    |> Enum.concat(Map.keys(new_record))
    |> Enum.uniq()
    |> Enum.reject(&(&1 == key))
    |> Enum.reduce(%{}, fn field, acc ->
      old_value = Map.get(old_record, field, @missing)
      new_value = Map.get(new_record, field, @missing)

      if old_value === new_value do
        acc
      else
        Map.put(acc, field, {old_value, new_value})
      end
    end)
  end
end