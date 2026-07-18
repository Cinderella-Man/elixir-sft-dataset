  test "empty string returns error" do
    assert {:error, :empty_file} = LogfmtValidator.validate_string("", @basic_schema)
  end