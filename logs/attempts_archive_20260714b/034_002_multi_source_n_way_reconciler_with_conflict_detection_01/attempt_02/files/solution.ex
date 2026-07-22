defmodule MultiSourceReconciler do
  @moduledoc """
  Reconciles records coming from more than two sources at once.

  Records are keyed by a shared composite key (one or more fields). For every
  distinct composite key found across all sources, `reconcile/2` reports:

    * which sources have a record for that key (`:present_in`);
    * which sources are missing it (`:missing_from`);
    * the full original record from each present source (`:records`);
    * the fields on which the present sources disagree (`:conflicts`).

  The module is pure: it performs no I/O, spawns no processes, and relies only
  on the Elixir standard library.

  ## Key matching

  Two records refer to the same entity if and only if the values of *all* key
  fields are equal. A field that is absent from a record is treated as `nil`.

  ## Conflict detection

  A field is in conflict when the present sources do not all agree on its value
  (compared with `==`). A missing compare field is treated as `nil` for that
  source, so a source lacking the field conflicts with one that has it. When a
  field is in conflict, the reported inner map holds an entry for every present
  source.
  """

  @type source_name :: atom()
  @type record :: map()
  @type sources :: %{optional(source_name()) => [record()]}
  @type entry :: %{
          key: map(),
          present_in: [source_name()],
          missing_from: [source_name()],
          records: map(),
          conflicts: map()
        }

  @doc """
  Reconciles `sources` into a list of per-key entries.

  `sources` maps each source name (an atom) to its list of record maps. `opts`
  is a keyword list supporting:

    * `:key_fields` (required) — the list of atoms forming the composite key.
    * `:compare_fields` (optional) — the list of atoms to check for conflicts.
      When omitted or `nil`, every field appearing in any present record is
      checked, minus the key fields.

  Returns one entry per distinct composite key. The order of the entries, and
  the order of names within `:present_in`/`:missing_from`, are unspecified.

  ## Examples

      iex> sources = %{crm: [%{id: 1, name: "Ada"}], billing: [%{id: 1, name: "Ada"}]}
      iex> [entry] = MultiSourceReconciler.reconcile(sources, key_fields: [:id])
      iex> entry.key
      %{id: 1}
      iex> entry.conflicts
      %{}

  """
  @spec reconcile(sources(), keyword()) :: [entry()]
  def reconcile(sources, opts) do
    key_fields = Keyword.fetch!(opts, :key_fields)
    compare_fields = Keyword.get(opts, :compare_fields)
    source_names = Map.keys(sources)

    indexed =
      Map.new(sources, fn {name, records} ->
        {name, index_records(records, key_fields)}
      end)

    indexed
    |> Enum.flat_map(fn {_name, keyed} -> Map.keys(keyed) end)
    |> Enum.uniq()
    |> Enum.map(fn key_tuple ->
      build_entry(key_tuple, key_fields, compare_fields, indexed, source_names)
    end)
  end

  @spec index_records([record()], [atom()]) :: map()
  defp index_records(records, key_fields) do
    Enum.reduce(records, %{}, fn record, acc ->
      key_tuple = Enum.map(key_fields, fn field -> Map.get(record, field) end)
      Map.put(acc, key_tuple, record)
    end)
  end

  @spec build_entry([term()], [atom()], [atom()] | nil, map(), [source_name()]) :: entry()
  defp build_entry(key_tuple, key_fields, compare_fields, indexed, source_names) do
    present =
      Enum.filter(source_names, fn name ->
        Map.has_key?(Map.fetch!(indexed, name), key_tuple)
      end)

    records =
      Map.new(present, fn name ->
        {name, Map.fetch!(Map.fetch!(indexed, name), key_tuple)}
      end)

    fields = conflict_fields(compare_fields, records, key_fields)

    %{
      key: key_fields |> Enum.zip(key_tuple) |> Map.new(),
      present_in: present,
      missing_from: source_names -- present,
      records: records,
      conflicts: compute_conflicts(fields, records, present)
    }
  end

  @spec conflict_fields([atom()] | nil, map(), [atom()]) :: [atom()]
  defp conflict_fields(nil, records, key_fields) do
    records
    |> Enum.flat_map(fn {_name, record} -> Map.keys(record) end)
    |> Enum.uniq()
    |> Enum.reject(fn field -> field in key_fields end)
  end

  defp conflict_fields(compare_fields, _records, _key_fields), do: compare_fields

  @spec compute_conflicts([atom()], map(), [source_name()]) :: map()
  defp compute_conflicts(fields, records, present) do
    Enum.reduce(fields, %{}, fn field, acc ->
      value_map =
        Map.new(present, fn name ->
          {name, Map.get(Map.fetch!(records, name), field)}
        end)

      values = Enum.map(present, fn name -> Map.fetch!(value_map, name) end)

      if all_agree?(values) do
        acc
      else
        Map.put(acc, field, value_map)
      end
    end)
  end

  @spec all_agree?([term()]) :: boolean()
  defp all_agree?(values) do
    case values do
      [] -> true
      [first | rest] -> Enum.all?(rest, fn value -> value == first end)
    end
  end
end
