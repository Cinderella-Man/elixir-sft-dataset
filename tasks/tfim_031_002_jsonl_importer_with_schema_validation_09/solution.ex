  test "string field with non-string value produces a type error" do
    jsonl = ~s({"name": 123, "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "string"
  end