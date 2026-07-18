  test "theirs deleting a record we modified is a delete_modify blamed on theirs" do
    base = [%{id: 1, x: 1}]
    ours = [%{id: 1, x: 5}]
    theirs = []

    assert RecordMerge.merge(base, ours, theirs) ==
             %{
               merged: [],
               conflicts: [
                 %{id: 1, type: :delete_modify, deleted_by: :theirs, modified: %{id: 1, x: 5}}
               ]
             }
  end