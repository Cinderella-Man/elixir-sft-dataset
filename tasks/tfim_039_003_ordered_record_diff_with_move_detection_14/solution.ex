  test "same record is reported in changed and moved when it reordered and changed" do
    old = [%{id: 1, v: 1}, %{id: 2, v: 2}, %{id: 3, v: 3}]
    new = [%{id: 2, v: 2}, %{id: 3, v: 3}, %{id: 1, v: 99}]

    %{changed: changed, moved: moved} = OrderedRecordDiff.diff(old, new)

    assert moved == [%{id: 1, from: 0, to: 2}]
    assert changed == [%{id: 1, changes: %{v: {1, 99}}}]
  end