defmodule RecordDiffTest do
  use ExUnit.Case, async: true

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp sort_by_id(list), do: Enum.sort_by(list, & &1.id)

  defp changes_for(changed, id) do
    changed
    |> Enum.find(&(&1.id == id))
    |> Map.get(:changes)
  end

  # -------------------------------------------------------
  # Identical lists → empty diff
  # -------------------------------------------------------

  test "identical lists produce an empty diff" do
    records = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    assert RecordDiff.diff(records, records) == %{added: [], removed: [], changed: []}
  end

  test "two empty lists produce an empty diff" do
    assert RecordDiff.diff([], []) == %{added: [], removed: [], changed: []}
  end

  # -------------------------------------------------------
  # Additions
  # -------------------------------------------------------

  test "records in new but not old appear in :added" do
    old = [%{id: 1, name: "Alice"}]
    new = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert length(added) == 1
    assert hd(added).id == 2
    assert removed == []
    assert changed == []
  end

  test "completely new list: all records are :added" do
    old = []
    new = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert sort_by_id(added) == sort_by_id(new)
    assert removed == []
    assert changed == []
  end

  # -------------------------------------------------------
  # Removals
  # -------------------------------------------------------

  test "records in old but not new appear in :removed" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = [%{id: 1, name: "Alice"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert length(removed) == 1
    assert hd(removed).id == 2
    assert changed == []
  end

  test "completely removed list: all records are :removed" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = []

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert sort_by_id(removed) == sort_by_id(old)
    assert changed == []
  end

  # -------------------------------------------------------
  # Completely disjoint lists
  # -------------------------------------------------------

  test "completely disjoint lists: all old removed, all new added" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = [%{id: 3, name: "Carol"}, %{id: 4, name: "Dave"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert sort_by_id(added) == sort_by_id(new)
    assert sort_by_id(removed) == sort_by_id(old)
    assert changed == []
  end

  # -------------------------------------------------------
  # Field-level changes
  # -------------------------------------------------------

  test "changed record appears in :changed with correct field diff" do
    old = [%{id: 1, name: "Alice", age: 30}]
    new = [%{id: 1, name: "Alicia", age: 30}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert removed == []
    assert length(changed) == 1

    entry = hd(changed)
    assert entry.id == 1
    assert entry.changes == %{name: {"Alice", "Alicia"}}
  end

  test "multiple fields changed on the same record" do
    old = [%{id: 1, name: "Alice", age: 30, city: "NYC"}]
    new = [%{id: 1, name: "Alicia", age: 31, city: "NYC"}]

    changes = changes_for(RecordDiff.diff(old, new).changed, 1)

    assert changes == %{name: {"Alice", "Alicia"}, age: {30, 31}}
  end

  test "only field-level changes: no additions or removals" do
    old = [%{id: 1, score: 10}, %{id: 2, score: 20}]
    new = [%{id: 1, score: 15}, %{id: 2, score: 25}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert removed == []
    assert length(changed) == 2
    assert changes_for(changed, 1) == %{score: {10, 15}}
    assert changes_for(changed, 2) == %{score: {20, 25}}
  end

  test "unchanged records do not appear in :changed" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bobby"}]

    %{changed: changed} = RecordDiff.diff(old, new)

    assert length(changed) == 1
    assert hd(changed).id == 2
  end

  # -------------------------------------------------------
  # Field added/removed on same record
  # -------------------------------------------------------

  test "field added to existing record is reported as change with :missing old value" do
    old = [%{id: 1, name: "Alice"}]
    new = [%{id: 1, name: "Alice", email: "alice@example.com"}]

    changes = changes_for(RecordDiff.diff(old, new).changed, 1)

    assert changes == %{email: {:missing, "alice@example.com"}}
  end

  test "field removed from existing record is reported as change with :missing new value" do
    old = [%{id: 1, name: "Alice", email: "alice@example.com"}]
    new = [%{id: 1, name: "Alice"}]

    changes = changes_for(RecordDiff.diff(old, new).changed, 1)

    assert changes == %{email: {"alice@example.com", :missing}}
  end

  # -------------------------------------------------------
  # Custom key
  # -------------------------------------------------------

  test "custom :key option uses a different field as the record identifier" do
    old = [%{uuid: "aaa", value: 1}]
    new = [%{uuid: "aaa", value: 2}, %{uuid: "bbb", value: 9}]

    %{added: added, removed: removed, changed: changed} =
      RecordDiff.diff(old, new, key: :uuid)

    assert length(added) == 1
    assert hd(added).uuid == "bbb"
    assert removed == []
    assert length(changed) == 1
    assert hd(changed).uuid == "aaa"
    assert hd(changed).changes == %{value: {1, 2}}
  end

  # -------------------------------------------------------
  # Mixed scenario
  # -------------------------------------------------------

  test "mixed scenario: additions, removals, and changes together" do
    old = [
      %{id: 1, name: "Alice", age: 30},
      %{id: 2, name: "Bob", age: 25},
      %{id: 3, name: "Carol", age: 40}
    ]

    new = [
      %{id: 1, name: "Alice", age: 31},
      %{id: 3, name: "Carol", age: 40},
      %{id: 4, name: "Dave", age: 22}
    ]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert length(added) == 1
    assert hd(added).id == 4

    assert length(removed) == 1
    assert hd(removed).id == 2

    assert length(changed) == 1
    assert hd(changed).id == 1
    assert hd(changed).changes == %{age: {30, 31}}
  end
end
