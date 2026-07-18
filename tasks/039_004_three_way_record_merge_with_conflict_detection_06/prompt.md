# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `put_field` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `RecordMerge` that performs a **three-way merge** of record lists keyed by ID — the diff3 problem applied to lists of maps. Given a common ancestor plus two independently edited versions, it must produce the merged result and report the conflicts it could not resolve automatically.

I need these functions in the public API:
- `RecordMerge.merge(base_list, ours_list, theirs_list, opts \\ [])` where all three are lists of maps. It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with two keys:
  - `:merged` — the list of successfully merged records, sorted ascending by key value. Conflicted and deleted records are NOT included here.
  - `:conflicts` — the list of conflict descriptors, sorted ascending by key value.

Resolution rules, per id (looking at its presence/value in base `b`, ours `o`, theirs `t`):
- **Added on one side only** (absent in base): take that side's record into `:merged`.
- **Added on both sides** (absent in base, present in ours and theirs): if `o == t`, take it; otherwise emit a conflict `%{key => id, type: :add_add, ours: o, theirs: t}`.
- **Deleted on both sides** (in base, absent in ours and theirs): drop it (no merged record, no conflict).
- **Deleted on one side, unchanged on the other** (e.g. absent in ours, and `t == b`): drop it.
- **Deleted on one side, modified on the other**: emit `%{key => id, type: :delete_modify, deleted_by: :ours | :theirs, modified: <the surviving modified record>}`.
- **Present in base, ours, and theirs**: do a **field-level** three-way merge over the union of fields (using `:missing` for a field absent on a side):
  - if `ov == tv`, keep that value;
  - else if `ov == bv`, keep theirs (`tv`);
  - else if `tv == bv`, keep ours (`ov`);
  - else this field conflicts.
  A field whose resolved value is `:missing` is omitted from the merged record (it was deleted). If any field conflicts, emit `%{key => id, type: :modify_modify, fields: %{field => %{base: bv, ours: ov, theirs: tv}}}` (only the conflicting fields) and produce NO merged record for that id; otherwise put the reconstructed record into `:merged`.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.

## The module with `put_field` missing

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

  defp put_field(values, _field, :missing) do
    # TODO
  end

  defp present?(nil), do: false
  defp present?(_), do: true
end
```

Give me only the complete implementation of `put_field` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
