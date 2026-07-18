  test "boolean field must be actual JSON boolean" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": "true"}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "active", msg} = find_error(errors, 1, "active")
    assert msg =~ "boolean"
  end