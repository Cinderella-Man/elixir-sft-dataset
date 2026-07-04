  test "same field modified differently is a modify_modify conflict" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 2}]
    theirs = [%{id: 1, a: 3}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :modify_modify, fields: %{a: %{base: 1, ours: 2, theirs: 3}}}
               ]
             }
  end