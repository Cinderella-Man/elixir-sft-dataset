  test "field deleted by ours and modified by theirs conflicts with :missing on our side" do
    base = [%{id: 1, a: 1, b: 1}]
    ours = [%{id: 1, a: 1}]
    theirs = [%{id: 1, a: 1, b: 2}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{
                   id: 1,
                   type: :modify_modify,
                   fields: %{b: %{base: 1, ours: :missing, theirs: 2}}
                 }
               ]
             }
  end