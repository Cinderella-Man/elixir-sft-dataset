  test "identical nested lists produce an empty diff" do
    records = [%{id: 1, name: "A", address: %{city: "NYC", zip: "10001"}}]
    assert NestedRecordDiff.diff(records, records) ==
             %{added: [], removed: [], changed: []}
  end