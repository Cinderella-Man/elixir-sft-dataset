  test "malformed JSON produces an invalid JSON error" do
    jsonl = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}
    {this is not valid json}
    {"name": "Bob", "email": "bob@test.org", "age": 25, "active": false}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert length(valid) == 2
    assert length(errors) == 1
    assert {2, "_line", msg} = hd(errors)
    assert msg =~ "invalid JSON"
  end