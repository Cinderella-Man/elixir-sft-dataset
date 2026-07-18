  test "import_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             CsvImporter.import_file(
               "/tmp/does_not_exist_#{:rand.uniform(999_999)}.csv",
               @basic_schema
             )
  end