  test "record deleted on one side and unchanged on the other is dropped" do
    base = [%{id: 1, x: 1}]
    ours = []
    theirs = [%{id: 1, x: 1}]

    assert RecordMerge.merge(base, ours, theirs) == %{merged: [], conflicts: []}
  end