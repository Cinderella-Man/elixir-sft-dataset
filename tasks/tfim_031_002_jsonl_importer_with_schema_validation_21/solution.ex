  test "a single record can produce multiple errors" do
    jsonl = ~s({"name": null, "email": "bad", "age": "notnum", "active": "yes"}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    # name: required, email: format, age: type, active: type
    assert length(errors) >= 4
  end