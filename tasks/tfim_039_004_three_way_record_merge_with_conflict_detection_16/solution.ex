  test "field absent in base but added differently on both sides conflicts with :missing base" do
    base = [%{id: 1, a: 1}]
    ours = [%{id: 1, a: 1, b: 2}]
    theirs = [%{id: 1, a: 1, b: 3}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{
                   id: 1,
                   type: :modify_modify,
                   fields: %{b: %{base: :missing, ours: 2, theirs: 3}}
                 }
               ]
             }
  end