  test "delete on one side and modify on the other is a delete_modify conflict" do
    base = [%{id: 1, x: 1}]
    ours = []
    theirs = [%{id: 1, x: 5}]

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :delete_modify, deleted_by: :ours, modified: %{id: 1, x: 5}}
               ]
             }
  end