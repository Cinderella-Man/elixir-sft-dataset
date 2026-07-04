  test "records in old but not new appear in :removed" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = [%{id: 1, name: "Alice"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert length(removed) == 1
    assert hd(removed).id == 2
    assert changed == []
  end