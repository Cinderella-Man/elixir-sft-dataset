  test "import_file handles empty file" do
    path = "/tmp/csv_importer_empty_#{:rand.uniform(999_999)}.csv"
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:error, :empty_file} = CsvImporter.import_file(path, @basic_schema)
  end