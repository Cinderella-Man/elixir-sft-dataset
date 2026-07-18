  test "import_file reads and validates a real file" do
    path = "/tmp/jsonl_importer_test_#{:rand.uniform(999_999)}.jsonl"

    content = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}
    {"name": null, "email": "bad", "age": "nope", "active": "yes"}
    """

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = JsonlImporter.import_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 3
  end