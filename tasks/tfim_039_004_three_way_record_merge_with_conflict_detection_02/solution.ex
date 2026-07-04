  test "empty inputs merge to nothing" do
    assert RecordMerge.merge([], [], []) == %{merged: [], conflicts: []}
  end