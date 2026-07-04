  test "additions and removals return whole records" do
    old = [%{id: 1, address: %{city: "NYC"}}, %{id: 2, address: %{city: "LA"}}]
    new = [%{id: 1, address: %{city: "NYC"}}, %{id: 3, address: %{city: "SF"}}]

    %{added: added, removed: removed, changed: changed} = NestedRecordDiff.diff(old, new)

    assert added == [%{id: 3, address: %{city: "SF"}}]
    assert removed == [%{id: 2, address: %{city: "LA"}}]
    assert changed == []
  end