  test "list type validation" do
    schema = [field("tags", type: :list, required: false)]

    jsonl = """
    {"tags": ["a", "b"]}
    {"tags": "not a list"}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, schema)
    assert length(valid) == 1
    assert length(errors) == 1
    assert {2, "tags", msg} = find_error(errors, 2, "tags")
    assert msg =~ "list"
  end