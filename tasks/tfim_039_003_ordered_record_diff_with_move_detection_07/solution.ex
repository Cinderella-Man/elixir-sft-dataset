  test "record moved to the front is reported with from/to indices" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 3}, %{id: 1}, %{id: 2}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 0}]
  end