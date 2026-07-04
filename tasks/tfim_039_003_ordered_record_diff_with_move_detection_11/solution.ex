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