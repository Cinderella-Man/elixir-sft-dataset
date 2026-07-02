  test "identical lists produce an empty diff" do
    records = [%{id: 1, name: "Alice"}, %{id: 2, name: "Bob"}]
    assert RecordDiff.diff(records, records) == %{added: [], removed: [], changed: []}
  end