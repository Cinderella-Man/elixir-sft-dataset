  test "record deleted on both sides is dropped" do
    base = [%{id: 1, x: 1}]

    assert RecordMerge.merge(base, [], []) == %{merged: [], conflicts: []}
  end