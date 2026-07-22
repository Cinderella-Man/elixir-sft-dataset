Implement the private `resolve/5` function.

`resolve(id, key, b, o, t)` decides the fate of a single record id given its
value in the common ancestor (`b`), ours (`o`), and theirs (`t`). Any of `b`,
`o`, and `t` may be `nil`, meaning the record is absent on that side (use the
`present?/1` helper to test presence). The function must return one of:

  * `:drop` — no merged record and no conflict is produced for this id;
  * `{:merged, record}` — `record` goes into the `:merged` list;
  * `{:conflict, entry}` — `entry` (a conflict descriptor map) goes into the
    `:conflicts` list.

Branch on the presence triple `{present?(b), present?(o), present?(t)}`:

  * **Absent in base, present in ours and theirs** (`{false, true, true}`):
    if `o == t`, return `{:merged, o}`; otherwise return a conflict
    `%{key => id, type: :add_add, ours: o, theirs: t}`.
  * **Added on ours only** (`{false, true, false}`): return `{:merged, o}`.
  * **Added on theirs only** (`{false, false, true}`): return `{:merged, t}`.
  * **Present on all three sides** (`{true, true, true}`): delegate to the
    field-level merge via `merge_fields(id, key, b, o, t)`.
  * **Deleted on theirs, present on ours** (`{true, true, false}`): if `o == b`
    (ours is unchanged from base) return `:drop`; otherwise return a conflict
    `%{key => id, type: :delete_modify, deleted_by: :theirs, modified: o}`.
  * **Deleted on ours, present on theirs** (`{true, false, true}`): if `t == b`
    (theirs is unchanged from base) return `:drop`; otherwise return a conflict
    `%{key => id, type: :delete_modify, deleted_by: :ours, modified: t}`.
  * **Deleted on both sides** (`{true, false, false}`): return `:drop`.

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
    # TODO
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