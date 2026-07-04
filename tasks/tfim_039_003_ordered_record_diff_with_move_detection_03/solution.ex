  test "two empty lists produce an empty diff" do
    assert OrderedRecordDiff.diff([], []) ==
             %{added: [], removed: [], changed: [], moved: []}
  end