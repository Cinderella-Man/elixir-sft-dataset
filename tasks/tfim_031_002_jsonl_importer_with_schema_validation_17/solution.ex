  test "invalid email format produces a format error" do
    jsonl = ~s({"name": "Alice", "email": "not-an-email", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "email", msg} = find_error(errors, 1, "email")
    assert msg =~ "format"
  end