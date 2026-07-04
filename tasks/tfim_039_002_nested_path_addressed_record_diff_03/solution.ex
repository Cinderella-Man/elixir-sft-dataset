  test "two empty lists produce an empty diff" do
    assert NestedRecordDiff.diff([], []) == %{added: [], removed: [], changed: []}
  end