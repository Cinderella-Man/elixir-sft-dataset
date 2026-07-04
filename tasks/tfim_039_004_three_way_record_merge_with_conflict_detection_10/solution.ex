  test "record added on only one side is taken cleanly" do
    base = []
    ours = [%{id: 1, x: 1}]
    theirs = []

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, x: 1}], conflicts: []}
  end