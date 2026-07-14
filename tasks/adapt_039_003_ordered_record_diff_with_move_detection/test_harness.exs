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
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 3, v: 3}, %{id: 1, v: 10}, %{id: 4, v: 4}]

    %{added: added, removed: removed, changed: changed, moved: moved} =
      OrderedRecordDiff.diff(old, new)

    assert added == [%{id: 4, v: 4}]
    assert removed == [%{id: 2, v: 2}]
    assert changed == [%{id: 1, changes: %{v: {1, 10}}}]
    assert moved == [%{id: 3, from: 2, to: 0}]
  end

  test "custom :key option uses a different identifier field" do
    old = [%{sku: "a"}, %{sku: "b"}, %{sku: "c"}]
    new = [%{sku: "c"}, %{sku: "a"}, %{sku: "b"}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new, key: :sku)

    assert moved == [%{sku: "c", from: 2, to: 0}]
  end
end
