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