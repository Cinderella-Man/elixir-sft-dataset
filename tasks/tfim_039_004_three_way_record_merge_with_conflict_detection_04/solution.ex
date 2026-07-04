  test "identical edits on both sides merge without conflict" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 2}]
    theirs = [%{id: 1, a: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 2}], conflicts: []}
  end