  test "integer field with string value produces a type error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": "thirty", "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end