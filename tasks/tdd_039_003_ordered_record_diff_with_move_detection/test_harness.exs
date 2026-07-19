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
