# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

        if map_size(changes) == 0 do
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

## Test harness — implement the `# TODO` test

```elixir
defmodule OrderedRecordDiffTest do
  use ExUnit.Case, async: false

  test "identical ordered lists produce an empty diff" do
    records = [%{id: 1, name: "A"}, %{id: 2, name: "B"}]

    assert OrderedRecordDiff.diff(records, records) ==
             %{added: [], removed: [], changed: [], moved: []}
  end

  test "two empty lists produce an empty diff" do
    assert OrderedRecordDiff.diff([], []) ==
             %{added: [], removed: [], changed: [], moved: []}
  end

  test "appending records yields additions but no moves" do
    old = [%{id: 1}, %{id: 2}]
    new = [%{id: 1}, %{id: 2}, %{id: 3}]

    %{added: added, removed: removed, changed: changed, moved: moved} =
      OrderedRecordDiff.diff(old, new)

    assert added == [%{id: 3}]
    assert removed == []
    assert changed == []
    assert moved == []
  end

  test "removing a record does not count remaining relative order as a move" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 1}, %{id: 3}]

    %{removed: removed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert removed == [%{id: 2}]
    assert moved == []
  end

  test "record moved to the end is reported with from/to indices" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 2}, %{id: 3}, %{id: 1}]

    %{moved: moved, changed: changed} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 1, from: 0, to: 2}]
    assert changed == []
  end

  test "record moved to the front is reported with from/to indices" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 3}, %{id: 1}, %{id: 2}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 0}]
  end

  test "single interior swap flags exactly one moved record" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 1}, %{id: 3}, %{id: 2}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 1}]
  end

  test "field changes are independent of moves" do
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 1, v: 1}, %{id: 3, v: 3}, %{id: 2, v: 99}]

    %{changed: changed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 1}]
    assert changed == [%{id: 2, changes: %{v: {2, 99}}}]
  end

  test "field added/removed on an existing record uses :missing" do
    old = [%{id: 1, name: "A"}]
    new = [%{id: 1, name: "A", email: "a@x.com"}]

    %{changed: changed} = OrderedRecordDiff.diff(old, new)

    assert changed == [%{id: 1, changes: %{email: {:missing, "a@x.com"}}}]
  end

  test "mixed scenario: add, remove, change, and move together" do
    # TODO
  end

  test "custom :key option uses a different identifier field" do
    old = [%{sku: "a"}, %{sku: "b"}, %{sku: "c"}]
    new = [%{sku: "c"}, %{sku: "a"}, %{sku: "b"}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new, key: :sku)

    assert moved == [%{sku: "c", from: 2, to: 0}]
  end

  test "ambiguous LCS anchors the later new-sequence run and moves the earlier one" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}, %{id: 4}]
    new = [%{id: 3}, %{id: 4}, %{id: 1}, %{id: 2}]

    %{moved: moved, changed: changed} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 0}, %{id: 4, from: 3, to: 1}]
    assert changed == []
  end

  test "same record is reported in changed and moved when it reordered and changed" do
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 2, v: 2}, %{id: 3, v: 3}, %{id: 1, v: 99}]

    %{changed: changed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 1, from: 0, to: 2}]
    assert changed == [%{id: 1, changes: %{v: {1, 99}}}]
  end

  test "move indices are absolute positions despite surrounding adds and removes" do
    old = [%{id: 9}, %{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 7}, %{id: 8}, %{id: 3}, %{id: 1}, %{id: 2}]

    %{added: added, removed: removed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert added == [%{id: 7}, %{id: 8}]
    assert removed == [%{id: 9}]
    assert moved == [%{id: 3, from: 3, to: 2}]
  end

  test "field dropped from an existing record reports :missing on the new side" do
    old = [%{id: 1, name: "A", email: "a@x.com"}]
    new = [%{id: 1, name: "A"}]

    %{changed: changed} = OrderedRecordDiff.diff(old, new)

    assert changed == [%{id: 1, changes: %{email: {"a@x.com", :missing}}}]
  end

  test "multiple changed records are listed following new_list order" do
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 3, v: 30}, %{id: 2, v: 20}, %{id: 1, v: 10}]

    %{changed: changed} = OrderedRecordDiff.diff(old, new)

    assert changed == [
             %{id: 3, changes: %{v: {3, 30}}},
             %{id: 2, changes: %{v: {2, 20}}},
             %{id: 1, changes: %{v: {1, 10}}}
           ]
  end

  test "changed entries key their id under the custom :key option field" do
    old = [%{sku: "a", v: 1}, %{sku: "b", v: 2}]
    new = [%{sku: "a", v: 1}, %{sku: "b", v: 22}]

    %{changed: changed, moved: moved} = OrderedRecordDiff.diff(old, new, key: :sku)

    assert changed == [%{sku: "b", changes: %{v: {2, 22}}}]
    assert moved == []
  end
end
```
