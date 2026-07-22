Implement the private `merge_fields/5` function. It is called with `(id, key, b, o, t)`
when a record is present in all three of base (`b`), ours (`o`), and theirs (`t`), and it
performs a field-level three-way merge over the union of the three maps' keys (sorted
ascending). For each field, read the base, ours, and theirs values, using `:missing` when
a field is absent on that side. Resolve each field with these rules, in order:

  * if `ov == tv`, keep that value;
  * else if `ov == bv`, the field was changed only on theirs, so keep `tv`;
  * else if `tv == bv`, the field was changed only on ours, so keep `ov`;
  * otherwise the field conflicts — record it under `field` as
    `%{base: bv, ours: ov, theirs: tv}`.

Accumulate the resolved values into a record and the conflicting fields into a conflict
map. Use `put_field/3` to add resolved values so that a resolved value of `:missing` (the
field was deleted) is omitted from the reconstructed record. If there are no conflicting
fields, return `{:merged, values}` with the reconstructed record. Otherwise, produce no
merged record and return `{:conflict, %{key => id, type: :modify_modify, fields: conflicts}}`
containing only the conflicting fields.

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
    key = Keyword.get(opts, :key, :id)

    base = index_by(base_list, key)
    ours = index_by(ours_list, key)
    theirs = index_by(theirs_list, key)

    ids =
      (Map.keys(base) ++ Map.keys(ours) ++ Map.keys(theirs))
      |> Enum.uniq()
      |> Enum.sort()

    {merged, conflicts} =
      Enum.reduce(ids, {[], []}, fn id, {merged, conflicts} ->
        b = Map.get(base, id)
        o = Map.get(ours, id)
        t = Map.get(theirs, id)

        case resolve(id, key, b, o, t) do
          :drop -> {merged, conflicts}
          {:merged, record} -> {[record | merged], conflicts}
          {:conflict, entry} -> {merged, [entry | conflicts]}
        end
      end)

    %{merged: Enum.reverse(merged), conflicts: Enum.reverse(conflicts)}
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
    # TODO
  end

  defp put_field(values, _field, :missing), do: values
  defp put_field(values, field, value), do: Map.put(values, field, value)

  defp present?(nil), do: false
  defp present?(_), do: true
end
```