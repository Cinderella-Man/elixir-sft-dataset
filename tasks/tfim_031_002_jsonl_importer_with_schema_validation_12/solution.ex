  test "valid integer passes" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [_], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end