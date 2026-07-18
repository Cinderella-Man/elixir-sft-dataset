  test "move indices are absolute positions despite surrounding adds and removes" do
    old = [%{id: 9}, %{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 7}, %{id: 8}, %{id: 3}, %{id: 1}, %{id: 2}]

    %{added: added, removed: removed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert added == [%{id: 7}, %{id: 8}]
    assert removed == [%{id: 9}]
    assert moved == [%{id: 3, from: 3, to: 2}]
  end