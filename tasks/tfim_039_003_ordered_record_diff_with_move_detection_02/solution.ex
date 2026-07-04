  test "identical ordered lists produce an empty diff" do
    records = [%{id: 1, name: "A"}, %{id: 2, name: "B"}]

    assert OrderedRecordDiff.diff(records, records) ==
             %{added: [], removed: [], changed: [], moved: []}
  end