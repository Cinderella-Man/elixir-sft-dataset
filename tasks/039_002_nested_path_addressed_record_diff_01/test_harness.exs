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
    old = [%{id: 1, a: %{b: %{c: 1}}}]
    new = [%{id: 1, a: %{b: %{c: 2}}}]

    assert changes_for(NestedRecordDiff.diff(old, new).changed, 1) ==
             %{"a.b.c" => {1, 2}}
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
end
