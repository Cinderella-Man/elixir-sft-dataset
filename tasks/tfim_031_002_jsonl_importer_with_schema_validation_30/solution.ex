  test "import_file handles empty file" do
    path = "/tmp/jsonl_importer_empty_#{:rand.uniform(999_999)}.jsonl"
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:error, :empty_file} = JsonlImporter.import_file(path, @basic_schema)
  end