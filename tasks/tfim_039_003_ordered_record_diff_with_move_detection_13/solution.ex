  test "ambiguous LCS anchors the later new-sequence run and moves the earlier one" do
    old = [%{id: 1}, %{id: 2}, %{id: 3}, %{id: 4}]
    new = [%{id: 3}, %{id: 4}, %{id: 1}, %{id: 2}]

    %{moved: moved, changed: changed} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 3, from: 2, to: 0}, %{id: 4, from: 3, to: 1}]
    assert changed == []
  end