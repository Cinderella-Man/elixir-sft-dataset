  test "records in new but not old appear in :added" do
    old = [%{id: 1, name: "Alice"}]
    new = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert length(added) == 1
    assert hd(added).id == 2
    assert removed == []
    assert changed == []
  end