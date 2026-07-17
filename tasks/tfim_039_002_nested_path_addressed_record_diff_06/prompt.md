# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule NestedRecordDiff do
  @moduledoc """
  Compares two versions of a record list keyed by a unique ID field and
  produces a structured diff. Unlike a shallow diff, nested maps are compared
  recursively and every change is addressed by a dotted path string
  (e.g. `"address.city"`).
  """

  @doc """
  Compares `old_list` and `new_list` (both lists of possibly-nested maps) and
  returns `%{added: [...], removed: [...], changed: [...]}`.

  Options:

    * `:key` — atom used as the unique record identifier (defaults to `:id`).

  Each `:changed` entry is `%{key => id, changes: %{path_string => {old, new}}}`.
  """
  @spec diff([map()], [map()], keyword()) :: %{
          added: [map()],
          removed: [map()],
          changed: [map()]
        }
  def diff(old_list, new_list, opts \\ []) do
    key = Keyword.get(opts, :key, :id)

    old_index = index_by(old_list, key)
    new_index = index_by(new_list, key)

    old_keys = old_index |> Map.keys() |> MapSet.new()
    new_keys = new_index |> Map.keys() |> MapSet.new()

    added = new_keys |> MapSet.difference(old_keys) |> to_records(new_index)
    removed = old_keys |> MapSet.difference(new_keys) |> to_records(old_index)

    changed =
      old_keys
      |> MapSet.intersection(new_keys)
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.reduce([], fn kv, acc ->
        changes = deep_changes(Map.fetch!(old_index, kv), Map.fetch!(new_index, kv))

        if map_size(changes) == 0 do
          acc
        else
          [%{key => kv, changes: changes} | acc]
        end
      end)
      |> Enum.reverse()

    %{added: added, removed: removed, changed: changed}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp index_by(records, key) do
    Map.new(records, fn record -> {Map.fetch!(record, key), record} end)
  end

  defp to_records(key_set, index) do
    key_set
    |> MapSet.to_list()
    |> Enum.sort()
    |> Enum.map(&Map.fetch!(index, &1))
  end

  defp deep_changes(old_map, new_map) do
    deep_changes(old_map, new_map, "", %{})
  end

  defp deep_changes(old_map, new_map, prefix, acc) do
    fields =
      (Map.keys(old_map) ++ Map.keys(new_map))
      |> Enum.uniq()
      |> Enum.sort()

    Enum.reduce(fields, acc, fn field, acc ->
      path = join(prefix, field)
      old_value = Map.get(old_map, field, :missing)
      new_value = Map.get(new_map, field, :missing)

      cond do
        is_map(old_value) and is_map(new_value) ->
          deep_changes(old_value, new_value, path, acc)

        old_value == new_value ->
          acc

        true ->
          Map.put(acc, path, {old_value, new_value})
      end
    end)
  end

  defp join("", field), do: to_string(field)
  defp join(prefix, field), do: prefix <> "." <> to_string(field)
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule NestedRecordDiffTest do
  use ExUnit.Case, async: false

  defp changes_for(changed, id) do
    changed
    |> Enum.find(&(&1.id == id))
    |> Map.get(:changes)
  end

  test "identical nested lists produce an empty diff" do
    records = [%{id: 1, name: "A", address: %{city: "NYC", zip: "10001"}}]

    assert NestedRecordDiff.diff(records, records) ==
             %{added: [], removed: [], changed: []}
  end

  test "two empty lists produce an empty diff" do
    assert NestedRecordDiff.diff([], []) == %{added: [], removed: [], changed: []}
  end

  test "nested leaf change is reported with a dotted path" do
    old = [%{id: 1, name: "A", address: %{city: "NYC", zip: "10001"}}]
    new = [%{id: 1, name: "A", address: %{city: "LA", zip: "10001"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address.city" => {"NYC", "LA"}}
  end

  test "top-level and nested changes coexist" do
    old = [%{id: 1, name: "A", address: %{city: "NYC"}}]
    new = [%{id: 1, name: "Alice", address: %{city: "LA"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"name" => {"A", "Alice"}, "address.city" => {"NYC", "LA"}}
  end

  test "deeply nested leaf change builds a multi-segment path" do
    # TODO
  end

  test "nested leaf added inside an existing map uses :missing old value" do
    old = [%{id: 1, address: %{city: "NYC"}}]
    new = [%{id: 1, address: %{city: "NYC", country: "US"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address.country" => {:missing, "US"}}
  end

  test "nested leaf removed inside an existing map uses :missing new value" do
    old = [%{id: 1, address: %{city: "NYC", country: "US"}}]
    new = [%{id: 1, address: %{city: "NYC"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address.country" => {"US", :missing}}
  end

  test "map replaced by a scalar reports the whole value at the field path" do
    old = [%{id: 1, address: %{city: "NYC"}}]
    new = [%{id: 1, address: "unknown"}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address" => {%{city: "NYC"}, "unknown"}}
  end

  test "additions and removals return whole records" do
    old = [%{id: 1, address: %{city: "NYC"}}, %{id: 2, address: %{city: "LA"}}]
    new = [%{id: 1, address: %{city: "NYC"}}, %{id: 3, address: %{city: "SF"}}]

    %{added: added, removed: removed, changed: changed} = NestedRecordDiff.diff(old, new)

    assert added == [%{id: 3, address: %{city: "SF"}}]
    assert removed == [%{id: 2, address: %{city: "LA"}}]
    assert changed == []
  end

  test "unchanged nested records do not appear in :changed" do
    old = [%{id: 1, a: %{b: 1}}, %{id: 2, a: %{b: 2}}]
    new = [%{id: 1, a: %{b: 1}}, %{id: 2, a: %{b: 99}}]

    %{changed: changed} = NestedRecordDiff.diff(old, new)

    assert length(changed) == 1
    assert hd(changed).id == 2
    assert hd(changed).changes == %{"a.b" => {2, 99}}
  end

  test "custom :key option uses a different identifier field" do
    old = [%{uuid: "aaa", meta: %{v: 1}}]
    new = [%{uuid: "aaa", meta: %{v: 2}}, %{uuid: "bbb", meta: %{v: 9}}]

    %{added: added, changed: changed} = NestedRecordDiff.diff(old, new, key: :uuid)

    assert added == [%{uuid: "bbb", meta: %{v: 9}}]
    assert length(changed) == 1
    assert hd(changed).uuid == "aaa"
    assert hd(changed).changes == %{"meta.v" => {1, 2}}
  end

  test "multiple nested branches change on the same record" do
    old = [%{id: 1, home: %{city: "NYC"}, work: %{city: "NJ"}}]
    new = [%{id: 1, home: %{city: "LA"}, work: %{city: "SF"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"home.city" => {"NYC", "LA"}, "work.city" => {"NJ", "SF"}}
  end

  test "map appearing where the field was absent reports the whole map at the field path" do
    old = [%{id: 1, name: "A"}]
    new = [%{id: 1, name: "A", address: %{city: "NYC", zip: "10001"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address" => {:missing, %{city: "NYC", zip: "10001"}}}
  end

  test "scalar replaced by a map reports the whole value at the field path" do
    old = [%{id: 1, address: "unknown"}]
    new = [%{id: 1, address: %{city: "NYC"}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"address" => {"unknown", %{city: "NYC"}}}
  end

  test "top-level leaf added and removed both use :missing on the absent side" do
    old = [%{id: 1, name: "A"}, %{id: 2, name: "B", nickname: "Bee"}]
    new = [%{id: 1, name: "A", nickname: "Ace"}, %{id: 2, name: "B"}]

    %{changed: changed} = NestedRecordDiff.diff(old, new)

    assert changes_for(changed, 1) == %{"nickname" => {:missing, "Ace"}}
    assert changes_for(changed, 2) == %{"nickname" => {"Bee", :missing}}
  end

  test "default key is :id even when records also carry a uuid field" do
    old = [%{id: 1, uuid: "aaa", meta: %{v: 1}}]
    new = [%{id: 1, uuid: "bbb", meta: %{v: 2}}]

    %{added: added, removed: removed, changed: changed} = NestedRecordDiff.diff(old, new)

    assert added == []
    assert removed == []
    assert length(changed) == 1
    assert hd(changed).id == 1
    assert hd(changed).changes == %{"uuid" => {"aaa", "bbb"}, "meta.v" => {1, 2}}
  end

  test "nested map replaced by a scalar deeper down does not recurse" do
    old = [%{id: 1, a: %{b: %{c: 1, d: 2}}}]
    new = [%{id: 1, a: %{b: 5}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"a.b" => {%{c: 1, d: 2}, 5}}
  end

  test "added, removed and changed records are reported together in one diff" do
    old = [
      %{id: 1, a: %{b: 1}},
      %{id: 2, a: %{b: 2}},
      %{id: 3, a: %{b: 3}}
    ]

    new = [
      %{id: 1, a: %{b: 1}},
      %{id: 3, a: %{b: 30}},
      %{id: 4, a: %{b: 4}}
    ]

    %{added: added, removed: removed, changed: changed} = NestedRecordDiff.diff(old, new)

    assert added == [%{id: 4, a: %{b: 4}}]
    assert removed == [%{id: 2, a: %{b: 2}}]
    assert length(changed) == 1
    assert hd(changed).id == 3
    assert hd(changed).changes == %{"a.b" => {3, 30}}
  end
end
```
