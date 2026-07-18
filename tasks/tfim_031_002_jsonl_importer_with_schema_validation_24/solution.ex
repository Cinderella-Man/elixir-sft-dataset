  test "empty string returns error" do
    assert {:error, :empty_file} = JsonlImporter.import_string("", @basic_schema)
  end