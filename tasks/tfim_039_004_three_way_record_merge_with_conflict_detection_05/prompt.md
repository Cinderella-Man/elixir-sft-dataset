# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  defp put_field(values, _field, :missing), do: values
  defp put_field(values, field, value), do: Map.put(values, field, value)

  defp present?(nil), do: false
  defp present?(_), do: true
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule RecordMergeTest do
  use ExUnit.Case, async: false

  test "empty inputs merge to nothing" do
    assert RecordMerge.merge([], [], []) == %{merged: [], conflicts: []}
  end

  test "non-overlapping field edits auto-merge" do
    base = [%{id: 1, a: 1, b: 1}]
    ours = [%{id: 1, a: 2, b: 1}]
    theirs = [%{id: 1, a: 1, b: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 2, b: 2}], conflicts: []}
  end

  test "identical edits on both sides merge without conflict" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 2}]
    theirs = [%{id: 1, a: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 2}], conflicts: []}
  end

  test "same field modified differently is a modify_modify conflict" do
    # TODO
  end

  test "field added by one side only is merged in" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 1, b: 2}]
    theirs = [%{id: 1, a: 1}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 1, b: 2}], conflicts: []}
  end

  test "field deleted by one side and unchanged on the other is removed from the record" do
    base = [%{id: 1, a: 1, b: 2}]
    ours = [%{id: 1, a: 1}]
    theirs = [%{id: 1, a: 1, b: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 1}], conflicts: []}
  end

  test "record added on both sides identically is merged" do
    base = []
    ours = [%{id: 1, x: 1}]
    theirs = [%{id: 1, x: 1}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, x: 1}], conflicts: []}
  end

  test "record added differently on both sides is an add_add conflict" do
    base = []
    ours = [%{id: 1, x: 1}]
    theirs = [%{id: 1, x: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [%{id: 1, type: :add_add, ours: %{id: 1, x: 1}, theirs: %{id: 1, x: 2}}]
             }
  end

  test "record added on only one side is taken cleanly" do
    base = []
    ours = [%{id: 1, x: 1}]
    theirs = []

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, x: 1}], conflicts: []}
  end

  test "record deleted on both sides is dropped" do
    base = [%{id: 1, x: 1}]

    assert RecordMerge.merge(base, [], []) == %{merged: [], conflicts: []}
  end

  test "record deleted on one side and unchanged on the other is dropped" do
    base = [%{id: 1, x: 1}]
    ours = []
    theirs = [%{id: 1, x: 1}]

    assert RecordMerge.merge(base, ours, theirs) == %{merged: [], conflicts: []}
  end

  test "delete on one side and modify on the other is a delete_modify conflict" do
    base = [%{id: 1, x: 1}]
    ours = []
    theirs = [%{id: 1, x: 5}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :delete_modify, deleted_by: :ours, modified: %{id: 1, x: 5}}
               ]
             }
  end

  test "custom :key option is honored" do
    base = [%{sku: "a", qty: 1}]
    ours = [%{sku: "a", qty: 2}]
    theirs = [%{sku: "a", qty: 1}]

    assert RecordMerge.merge(base, ours, theirs, key: :sku) ==
             %{merged: [%{sku: "a", qty: 2}], conflicts: []}
  end

  test "mixed multi-record scenario keeps results sorted by key" do
    base = [%{id: 1, a: 1}, %{id: 2, a: 2}, %{id: 3, a: 3}]
    ours = [%{id: 1, a: 10}, %{id: 3, a: 3}, %{id: 4, a: 4}]
    theirs = [%{id: 1, a: 1}, %{id: 2, a: 2}, %{id: 3, a: 30}]

    %{merged: merged, conflicts: conflicts} = RecordMerge.merge(base, ours, theirs)

    # id 1: only ours changed -> keep ours. id 2: only theirs (deleted by ours, unchanged theirs) -> dropped.
    # id 3: only theirs changed -> keep theirs. id 4: added by ours -> keep.
    assert merged == [%{id: 1, a: 10}, %{id: 3, a: 30}, %{id: 4, a: 4}]
    assert conflicts == []
  end
end
```
