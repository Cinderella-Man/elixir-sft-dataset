  test "completely new list: all records are :added" do
    old = []
    new = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert sort_by_id(added) == sort_by_id(new)
    assert removed == []
    assert changed == []
  end