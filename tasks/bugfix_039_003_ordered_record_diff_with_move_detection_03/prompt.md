# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Write me an Elixir module called `OrderedRecordDiff` that compares two versions of a record list keyed by ID and produces a structured diff that is **order-aware**: the lists are treated as ordered sequences, so besides additions, removals, and field-level changes, the diff must also detect records that were **moved** to a different position.

I need these functions in the public API:
- `OrderedRecordDiff.diff(old_list, new_list, opts \\ [])` where both lists are lists of maps. It should accept a `:key` option that is an atom specifying which field to use as the unique identifier (defaults to `:id`). It should return a map with four keys:
  - `:added` — whole records present in `new_list` but not in `old_list`, in `new_list` order
  - `:removed` — whole records present in `old_list` but not in `new_list`, in `old_list` order
  - `:changed` — one entry per record present in both lists whose fields differ, in `new_list` order. Each entry is `%{key => id, changes: %{field => {old_value, new_value}}}` (fields present in only one version use `:missing` as the absent-side value, exactly as in the base task). Only fields whose values differ between the two versions appear in `changes`; a record whose fields are all equal is omitted from `:changed` entirely.
  - `:moved` — one entry per record whose relative order changed, in `new_list` order. Each entry is `%{key => id, from: old_index, to: new_index}` where the indices are the record's absolute 0-based positions in `old_list` and `new_list`

Move-detection rules:
- Consider only the records that exist in BOTH lists. Take their id sequence in old order and in new order and compute a Longest Common Subsequence (LCS) of the two. The ids that belong to the LCS are the "stable" anchors; every other common id is reported as moved. When the LCS is ambiguous (several are equally long), prefer, at each step, the match that keeps the later element of the new sequence (i.e. when the "skip in new" and "skip in old" branches tie in length, keep the "skip in new" branch).
- A record can appear in BOTH `:changed` and `:moved` if it was reordered and its fields also changed — the two are independent.
- Field-level changes are computed for every common record regardless of whether it moved.

The function must be pure — no processes, no state, no side effects. Use only the Elixir standard library.

Give me the complete module in a single file.

## The buggy module

```elixir
defmodule OrderedRecordDiff do
  @moduledoc """
  Order-aware diff of two record lists keyed by a unique ID field. In addition
  to `:added`, `:removed`, and field-level `:changed`, it reports `:moved`
  records whose relative order changed, using a Longest Common Subsequence of
  the common id sequences to identify the stable anchors.
  """

  @doc """
  Compares `old_list` and `new_list` (both lists of maps) and returns
  `%{added: [...], removed: [...], changed: [...], moved: [...]}`.

  Options:

    * `:key` — atom used as the unique record identifier (defaults to `:id`).
  """
  @spec diff([map()], [map()], keyword()) :: %{
          added: [map()],
          removed: [map()],
          changed: [map()],
          moved: [map()]
        }
  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_keys = Enum.map(old_list, &Map.fetch!(&1, key))
    new_keys = Enum.map(new_list, &Map.fetch!(&1, key))

    old_set = MapSet.new(old_keys)
    new_set = MapSet.new(new_keys)

    added = Enum.reject(new_list, &MapSet.member?(old_set, Map.fetch!(&1, key)))
    removed = Enum.reject(old_list, &MapSet.member?(new_set, Map.fetch!(&1, key)))

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)
    old_pos = positions(old_list, key)
    new_pos = positions(new_list, key)

    common_new_seq = Enum.filter(new_keys, &MapSet.member?(old_set, &1))
    common_old_seq = Enum.filter(old_keys, &MapSet.member?(new_set, &1))
    stable = MapSet.new(lcs(common_old_seq, common_new_seq))

    changed =
      common_new_seq
      |> Enum.reduce([], fn kv, acc ->
        changes = diff_records(Map.fetch!(old_index, kv), Map.fetch!(new_index, kv))

        if map_size(changes) == 1 do
          acc
        else
          [%{key => kv, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    moved =
      common_new_seq
      |> Enum.reject(&MapSet.member?(stable, &1))
      |> Enum.map(fn kv ->
        %{key => kv, from: Map.fetch!(old_pos, kv), to: Map.fetch!(new_pos, kv)}
      end)

    %{added: added, removed: removed, changed: changed, moved: moved}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  defp positions(records, key) do
    records
    |> Enum.with_index()
    |> Map.new(fn {record, index} -> {Map.fetch!(record, key), index} end)
  end

  defp diff_records(old_record, new_record) do
    fields =
      (Map.keys(old_record) ++ Map.keys(new_record))
      |> Enum.uniq()

    Enum.reduce(fields, %{}, fn field, acc ->
      old_value = Map.get(old_record, field, :missing)
      new_value = Map.get(new_record, field, :missing)

      if old_value == new_value do
        acc
      else
        Map.put(acc, field, {old_value, new_value})
      end
    end)
  end

  # Longest Common Subsequence via bottom-up dynamic programming. On ties the
  # "skip in new" branch (j + 1) is preferred, keeping later new-sequence
  # elements as anchors.
  defp lcs(a_list, b_list) do
    a = List.to_tuple(a_list)
    b = List.to_tuple(b_list)
    n = tuple_size(a)
    m = tuple_size(b)

    indices = for i <- Enum.reverse(0..n), j <- Enum.reverse(0..m), do: {i, j}

    table =
      Enum.reduce(indices, %{}, fn {i, j}, table ->
        value =
          cond do
            i == n or j == m ->
              []

            elem(a, i) == elem(b, j) ->
              [elem(a, i) | Map.fetch!(table, {i + 1, j + 1})]

            true ->
              right = Map.fetch!(table, {i, j + 1})
              down = Map.fetch!(table, {i + 1, j})
              if length(right) >= length(down), do: right, else: down
          end

        Map.put(table, {i, j}, value)
      end)

    Map.fetch!(table, {0, 0})
  end
end
```

## Failing test report

```
6 of 11 test(s) failed:

  * test identical ordered lists produce an empty diff
      
      
      Assertion with == failed
      code:  assert OrderedRecordDiff.diff(records, records) == %{added: [], removed: [], changed: [], moved: []}
      left:  %{removed: [], added: [], changed: [%{id: 1, changes: %{}}, %{id: 2, changes: %{}}], moved: []}
      right: %{removed: [], added: [], changed: [], moved: []}
      

  * test appending records yields additions but no moves
      
      
      Assertion with == failed
      code:  assert changed == []
      left:  [%{id: 1, changes: %{}}, %{id: 2, changes: %{}}]
      right: []
      

  * test record moved to the end is reported with from/to indices
      
      
      Assertion with == failed
      code:  assert changed == []
      left:  [%{id: 2, changes: %{}}, %{id: 3, changes: %{}}, %{id: 1, changes: %{}}]
      right: []
      

  * test field changes are independent of moves
      
      
      Assertion with == failed
      code:  assert changed == [%{id: 2, changes: %{v: {2, 99}}}]
      left:  [%{id: 1, changes: %{}}, %{id: 3, changes: %{}}]
      right: [%{id: 2, changes: %{v: {2, 99}}}]
      

  (…2 more)
```
