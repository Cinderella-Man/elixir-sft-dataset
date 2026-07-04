  test "appending records yields additions but no moves" do
    old = [%{id: 1}, %{id: 2}]
    new = [%{id: 1}, %{id: 2}, %{id: 3}]

    %{added: added, removed: removed, changed: changed, moved: moved} =
      OrderedRecordDiff.diff(old, new)

    assert added == [%{id: 3}]
    assert removed == []
    assert changed == []
    assert moved == []
  end