  test "BOM characters at start of file are stripped" do
    jsonl =
      "\xEF\xBB\xBF" <>
        ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert row["name"] == "Alice"
  end