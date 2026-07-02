  test "imports fully valid JSONL" do
    jsonl = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "score": 95.5, "active": true}
    {"name": "Bob", "email": "bob@test.org", "age": 25, "score": 88.0, "active": false}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [alice, bob] = valid
    assert alice["name"] == "Alice"
    assert alice["email"] == "alice@example.com"
    assert alice["age"] == 30
    assert bob["active"] == false
  end