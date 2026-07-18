  test "leading and trailing whitespace is trimmed from string values" do
    jsonl = ~s({"name": "  Alice  ", "email": " alice@example.com ", "age": 30, "active": true}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert row["name"] == "Alice"
    assert row["email"] == "alice@example.com"
  end