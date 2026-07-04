  test "record added on both sides identically is merged" do
    base = []
    ours = [%{id: 1, x: 1}]
    theirs = [%{id: 1, x: 1}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, x: 1}], conflicts: []}
  end