  test "empty file returns error" do
    assert {:error, :empty_file} = CsvImporter.import_string("", @basic_schema)
  end