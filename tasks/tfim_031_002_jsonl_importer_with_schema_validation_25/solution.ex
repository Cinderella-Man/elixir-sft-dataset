  test "string with only blank lines returns error" do
    assert {:error, :empty_file} = JsonlImporter.import_string("\n\n  \n", @basic_schema)
  end