  test "record added on the theirs side only is taken cleanly" do
    base = []
    ours = []
    theirs = [%{id: 7, x: 42}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 7, x: 42}], conflicts: []}
  end