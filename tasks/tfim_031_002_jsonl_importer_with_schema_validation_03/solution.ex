  test "valid records are returned as maps keyed by field names" do
    jsonl = ~s({"name": "Carol", "email": "carol@example.com", "age": 40, "active": true}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, "name")
    assert Map.has_key?(row, "email")
    assert Map.has_key?(row, "age")
    assert Map.has_key?(row, "active")
  end