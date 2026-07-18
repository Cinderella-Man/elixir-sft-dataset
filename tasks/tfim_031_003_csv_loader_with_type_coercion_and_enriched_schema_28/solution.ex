  test "empty string returns error" do
    assert {:error, :empty_file} = CsvLoader.load_string("", @basic_schema)
  end