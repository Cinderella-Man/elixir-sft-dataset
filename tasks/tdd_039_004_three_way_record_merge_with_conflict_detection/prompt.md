# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 2}]
    theirs = [%{id: 1, a: 3}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :modify_modify, fields: %{a: %{base: 1, ours: 2, theirs: 3}}}
               ]
             }
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

  test "theirs deleting a record we modified is a delete_modify blamed on theirs" do
    base = [%{id: 1, x: 1}]
    ours = [%{id: 1, x: 5}]
    theirs = []

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :delete_modify, deleted_by: :theirs, modified: %{id: 1, x: 5}}
               ]
             }
  end

  test "field absent in base but added differently on both sides conflicts with :missing base" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 1, b: 2}]
    theirs = [%{id: 1, a: 1, b: 3}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{
                   id: 1,
                   type: :modify_modify,
                   fields: %{b: %{base: :missing, ours: 2, theirs: 3}}
                 }
               ]
             }
  end

  test "field deleted by ours and modified by theirs conflicts with :missing on our side" do
    base = [%{id: 1, a: 1, b: 1}]
    ours = [%{id: 1, a: 1}]
    theirs = [%{id: 1, a: 1, b: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{
                   id: 1,
                   type: :modify_modify,
                   fields: %{b: %{base: 1, ours: :missing, theirs: 2}}
                 }
               ]
             }
  end

  test "conflict descriptors are keyed by the custom :key option field" do
    base = []
    ours = [%{sku: "a", qty: 1}]
    theirs = [%{sku: "a", qty: 2}]

    assert RecordMerge.merge(base, ours, theirs, key: :sku) ==
             %{
               merged: [],
               conflicts: [
                 %{
                   sku: "a",
                   type: :add_add,
                   ours: %{sku: "a", qty: 1},
                   theirs: %{sku: "a", qty: 2}
                 }
               ]
             }
  end

  test "modify_modify reports only conflicting fields and suppresses the merged record" do
    base = [%{id: 1, a: 1, b: 1, c: 1}]
    ours = [%{id: 1, a: 2, b: 1, c: 9}]
    theirs = [%{id: 1, a: 3, b: 5, c: 9}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :modify_modify, fields: %{a: %{base: 1, ours: 2, theirs: 3}}}
               ]
             }
  end

  test "record added on the theirs side only is taken cleanly" do
    base = []
    ours = []
    theirs = [%{id: 7, x: 42}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 7, x: 42}], conflicts: []}
  end

  test "record deleted by theirs while unchanged by ours is dropped" do
    base = [%{id: 1, x: 1}]
    ours = [%{id: 1, x: 1}]
    theirs = []

    assert RecordMerge.merge(base, ours, theirs) == %{merged: [], conflicts: []}
  end

  test "merged list is sorted ascending by key when inputs arrive out of key order" do
    # First appearance across the inputs is 20, 30, 10, 40; the result must be
    # ordered by key value, not by the order the records were supplied in.
    base = [%{id: 20, a: 1}, %{id: 30, a: 1}, %{id: 10, a: 1}]
    ours = [%{id: 20, a: 2}, %{id: 40, a: 4}, %{id: 10, a: 1}]
    theirs = [%{id: 10, a: 3}, %{id: 30, a: 1}, %{id: 20, a: 1}]

    # id 10: only theirs changed -> theirs. id 20: only ours changed -> ours.
    # id 30: deleted by ours, unchanged by theirs -> dropped. id 40: added by ours.
    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [%{id: 10, a: 3}, %{id: 20, a: 2}, %{id: 40, a: 4}],
               conflicts: []
             }
  end

  test "multiple conflicts of different types are sorted ascending by key" do
    # First appearance across the inputs is 5, 2, 9; conflicts must come back as 2, 5, 9.
    base = [%{id: 5, a: 1}, %{id: 2, a: 1}]
    ours = [%{id: 5, a: 2}, %{id: 9, z: 1}, %{id: 2, a: 2}]
    theirs = [%{id: 5, a: 3}, %{id: 9, z: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 2, type: :delete_modify, deleted_by: :theirs, modified: %{id: 2, a: 2}},
                 %{id: 5, type: :modify_modify, fields: %{a: %{base: 1, ours: 2, theirs: 3}}},
                 %{id: 9, type: :add_add, ours: %{id: 9, z: 1}, theirs: %{id: 9, z: 2}}
               ]
             }
  end

  test "sorting follows the custom :key field values, not input order" do
    # First appearance across the inputs is "c", "b", "a"; merged must come back as "a", "b".
    base = [%{sku: "c", q: 1}, %{sku: "b", q: 1}]
    ours = [%{sku: "c", q: 2}, %{sku: "b", q: 2}, %{sku: "a", q: 9}]
    theirs = [%{sku: "c", q: 3}, %{sku: "b", q: 1}]

    assert RecordMerge.merge(base, ours, theirs, key: :sku) ==
             %{
               merged: [%{sku: "a", q: 9}, %{sku: "b", q: 2}],
               conflicts: [
                 %{sku: "c", type: :modify_modify, fields: %{q: %{base: 1, ours: 2, theirs: 3}}}
               ]
             }
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
