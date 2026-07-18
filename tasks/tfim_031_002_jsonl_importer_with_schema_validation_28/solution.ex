  test "import_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             JsonlImporter.import_file(
               "/tmp/does_not_exist_#{:rand.uniform(999_999)}.jsonl",
               @basic_schema
             )
  end