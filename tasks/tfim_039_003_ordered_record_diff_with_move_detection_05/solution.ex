  test "removing a record does not count remaining relative order as a move" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 1}, %{id: 3}]

    %{removed: removed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert removed == [%{id: 2}]
    assert moved == []
  end