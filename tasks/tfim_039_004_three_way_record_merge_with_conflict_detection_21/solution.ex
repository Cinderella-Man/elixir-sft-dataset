  test "record deleted by theirs while unchanged by ours is dropped" do
    base = [%{id: 1, x: 1}]
    ours = [%{id: 1, x: 1}]
    theirs = []

    assert RecordMerge.merge(base, ours, theirs) == %{merged: [], conflicts: []}
  end