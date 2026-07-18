  test "integer field accepts a JSON number that is a whole number" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30.0, "active": true}\n)

    assert {:ok, [_], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end