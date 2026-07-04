  test "single interior swap flags exactly one moved record" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}]
    new = [%{id: 1}, %{id: 3}, %{id: 2}]

    %{moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 1}]
  end