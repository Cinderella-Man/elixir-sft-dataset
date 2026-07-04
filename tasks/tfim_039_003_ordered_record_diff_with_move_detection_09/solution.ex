  test "field changes are independent of moves" do
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 1, v: 1}, %{id: 3, v: 3}, %{id: 2, v: 99}]

    %{changed: changed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 1}]
    assert changed == [%{id: 2, changes: %{v: {2, 99}}}]
  end