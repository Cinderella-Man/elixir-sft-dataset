  test "completely removed list: all records are :removed" do
    old = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    new = []

    %{added: added, removed: removed, changed: changed} = RecordDiff.diff(old, new)

    assert added == []
    assert sort_by_id(removed) == sort_by_id(old)
    assert changed == []
  end