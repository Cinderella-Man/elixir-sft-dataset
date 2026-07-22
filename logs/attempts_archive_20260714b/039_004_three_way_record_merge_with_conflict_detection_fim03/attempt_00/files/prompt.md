Implement the public `merge/4` function. It takes `base_list`, `ours_list`, and `theirs_list` (all lists of maps) plus an `opts` keyword list, and returns `%{merged: [...], conflicts: [...]}`.

It must read the `:key` option (defaulting to `:id`) to determine which field is the unique record identifier. Using `index_by/2`, build three maps — `base`, `ours`, and `theirs` — that index each record list by its key value. Compute the sorted, de-duplicated list of all ids appearing across the three maps.

Fold over those ids, accumulating two lists (merged records and conflict descriptors). For each id, look up its record (or `nil`) in `base`, `ours`, and `theirs`, then delegate to `resolve/5`, which returns one of:

  * `:drop` — add nothing to either accumulator;
  * `{:merged, record}` — prepend `record` to the merged accumulator;
  * `{:conflict, entry}` — prepend `entry` to the conflicts accumulator.

Because the reduce prepends, reverse both accumulators before returning them so that `:merged` and `:conflicts` come out sorted ascending by key value. Return the final `%{merged: ..., conflicts: ...}` map. The function must be pure — no processes, no state, no side effects.

```elixir
defmodule RecordMerge do
  @moduledoc """
  Three-way merge (diff3) of record lists keyed by a unique ID field. Given a
  common ancestor plus two edited versions, it auto-merges non-overlapping
  changes and reports the conflicts it cannot resolve.
  """

  @doc """
  Three-way merge of `base_list`, `ours_list`, and `theirs_list` (all lists of
  maps). Returns `%{merged: [...], conflicts: [...]}`, both sorted ascending by
  key value.

  Options:

    * `:key` — atom used as the unique record identifier (defaults to `:id`).
  """
  @spec merge([map()], [map()], [map()], keyword()) :: %{
          merged: [map()],
          conflicts: [map()]
        }
  def merge(base_list, ours_list, theirs_list, opts \\ []) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  defp resolve(id, key, b, o, t) do
    case {present?(b), present?(o), present?(t)} do
      {false, true, true} ->
        if o == t do
          {:merged, o}
        else
          {:conflict, %{key => id, type: :add_add, ours: o, theirs: t}}
        end

      {false, true, false} ->
        {:merged, o}

      {false, false, true} ->
        {:merged, t}

      {true, true, true} ->
        merge_fields(id, key, b, o, t)

      {true, true, false} ->
        if o == b do
          :drop
        else
          {:conflict, %{key => id, type: :delete_modify, deleted_by: :theirs, modified: o}}
        end

      {true, false, true} ->
        if t == b do
          :drop
        else
          {:conflict, %{key => id, type: :delete_modify, deleted_by: :ours, modified: t}}
        end

      {true, false, false} ->
        :drop
    end
  end

  defp merge_fields(id, key, b, o, t) do
    fields =
      (Map.keys(b) ++ Map.keys(o) ++ Map.keys(t))
      |> Enum.uniq()
      |> Enum.sort()

    {values, conflicts} =
      Enum.reduce(fields, {%{}, %{}}, fn field, {values, conflicts} ->
        bv = Map.get(b, field, :missing)
        ov = Map.get(o, field, :missing)
        tv = Map.get(t, field, :missing)

        cond do
          ov == tv -> {put_field(values, field, ov), conflicts}
          ov == bv -> {put_field(values, field, tv), conflicts}
          tv == bv -> {put_field(values, field, ov), conflicts}
          true -> {values, Map.put(conflicts, field, %{base: bv, ours: ov, theirs: tv})}
        end
      end)

    if map_size(conflicts) == 0 do
      {:merged, values}
    else
      {:conflict, %{key => id, type: :modify_modify, fields: conflicts}}
    end
  end

  defp put_field(values, _field, :missing), do: values
  defp put_field(values, field, value), do: Map.put(values, field, value)

  defp present?(nil), do: false
  defp present?(_), do: true
end
```