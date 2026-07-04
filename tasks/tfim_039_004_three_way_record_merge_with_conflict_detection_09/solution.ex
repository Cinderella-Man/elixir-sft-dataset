  test "record added differently on both sides is an add_add conflict" do
    base = []
    ours = [%{id: 1, x: 1}]
    theirs = [%{id: 1, x: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [%{id: 1, type: :add_add, ours: %{id: 1, x: 1}, theirs: %{id: 1, x: 2}}]
             }
  end