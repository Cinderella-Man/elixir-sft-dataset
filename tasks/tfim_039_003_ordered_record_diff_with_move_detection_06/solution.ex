  test "record moved to the end is reported with from/to indices" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 2}, %{id: 3}, %{id: 1}]

    %{moved: moved, changed: changed} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 1, from: 0, to: 2}]
    assert changed == []
  end