  test "non-overlapping field edits auto-merge" do
    base = [%{id: 1, a: 1, b: 1}]
    ours = [%{id: 1, a: 2, b: 1}]
    theirs = [%{id: 1, a: 1, b: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 2, b: 2}], conflicts: []}
  end