# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `index_by` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

**Summary:** Implement an Elixir module `RecordMerge` that performs a three-way merge (the diff3 problem applied to lists of maps) of record lists keyed by ID: given a common ancestor plus two independently edited versions, produce the merged result and report the conflicts it could not resolve automatically.

**Public API**
- `RecordMerge.merge(base_list, ours_list, theirs_list, opts \\ [])` — all three arguments are lists of maps.
- Accepts a `:key` option, an atom specifying which field is the unique identifier; defaults to `:id`.
- Returns a map with two keys:
  - `:merged` — list of successfully merged records, sorted ascending by key value. Conflicted and deleted records are NOT included here.
  - `:conflicts` — list of conflict descriptors, sorted ascending by key value.

**Resolution rules (per id, from its presence/value in base `b`, ours `o`, theirs `t`)**
- Added on one side only (absent in base): take that side's record into `:merged`.
- Added on both sides (absent in base, present in ours and theirs): if `o == t`, take it; otherwise emit a conflict `%{key => id, type: :add_add, ours: o, theirs: t}`.
- Deleted on both sides (in base, absent in ours and theirs): drop it (no merged record, no conflict).
- Deleted on one side, unchanged on the other (e.g. absent in ours, and `t == b`): drop it.
- Deleted on one side, modified on the other: emit `%{key => id, type: :delete_modify, deleted_by: :ours | :theirs, modified: <the surviving modified record>}`.

**Present in base, ours, and theirs — field-level three-way merge over the union of fields (use `:missing` for a field absent on a side)**
- if `ov == tv`, keep that value;
- else if `ov == bv`, keep theirs (`tv`);
- else if `tv == bv`, keep ours (`ov`);
- else this field conflicts.
- A field whose resolved value is `:missing` is omitted from the merged record (it was deleted).
- If any field conflicts, emit `%{key => id, type: :modify_modify, fields: %{field => %{base: bv, ours: ov, theirs: tv}}}` (only the conflicting fields) and produce NO merged record for that id; otherwise put the reconstructed record into `:merged`.

**Constraints**
- Function must be pure — no processes, no state, no side effects.
- Use only the Elixir standard library.
- Deliver the complete module in a single file.

## The module with `index_by` missing

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
    # TODO
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

Reply with `index_by` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
