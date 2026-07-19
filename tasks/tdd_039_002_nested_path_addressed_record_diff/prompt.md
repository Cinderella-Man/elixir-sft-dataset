# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
