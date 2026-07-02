  test "required field that is null produces an error" do
    jsonl = ~s({"name": null, "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end