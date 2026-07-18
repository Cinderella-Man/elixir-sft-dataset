  test "valid boolean passes" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": false}\n)

    assert {:ok, [_], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end