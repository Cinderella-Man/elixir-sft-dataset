  test "modify_modify reports only conflicting fields and suppresses the merged record" do
    base = [%{id: 1, a: 1, b: 1, c: 1}]
    ours = [%{id: 1, a: 2, b: 1, c: 9}]
    theirs = [%{id: 1, a: 3, b: 5, c: 9}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :modify_modify, fields: %{a: %{base: 1, ours: 2, theirs: 3}}}
               ]
             }
  end