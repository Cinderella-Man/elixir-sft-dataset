  test "field added by one side only is merged in" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 1, b: 2}]
    theirs = [%{id: 1, a: 1}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 1, b: 2}], conflicts: []}
  end