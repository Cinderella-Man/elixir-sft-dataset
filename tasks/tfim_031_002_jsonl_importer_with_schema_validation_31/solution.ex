  test "all-optional schema with null values produces no errors" do
    schema = [
      field("a", required: false),
      field("b", required: false, type: :integer)
    ]

    jsonl = ~s({"a": null, "b": null}\n)

    assert {:ok, [_row], []} = JsonlImporter.import_string(jsonl, schema)
  end