  test "two empty lists produce an empty diff" do
    assert RecordDiff.diff([], []) == %{added: [], removed: [], changed: []}
  end