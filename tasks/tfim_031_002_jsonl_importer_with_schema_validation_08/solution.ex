  test "optional field that is missing does NOT produce an error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [_row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end