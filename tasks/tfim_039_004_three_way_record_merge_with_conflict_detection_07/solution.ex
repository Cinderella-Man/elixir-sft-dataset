  test "field deleted by one side and unchanged on the other is removed from the record" do
    base = [%{id: 1, a: 1, b: 2}]
    ours = [%{id: 1, a: 1}]
    theirs = [%{id: 1, a: 1, b: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{merged: [%{id: 1, a: 1}], conflicts: []}
  end