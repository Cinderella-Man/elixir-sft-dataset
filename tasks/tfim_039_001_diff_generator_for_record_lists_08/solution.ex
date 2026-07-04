  test "completely disjoint lists: all old removed, all new added" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = [%{id: 3, name: "Carol"}, %{id: 4, name: "Dave"}]

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert sort_by_id(added) == sort_by_id(new)
    assert sort_by_id(removed) == sort_by_id(old)
    assert changed == []
  end