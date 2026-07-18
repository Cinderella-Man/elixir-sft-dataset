  test "string with only blank lines returns error" do
    assert {:error, :empty_file} = LogfmtValidator.validate_string("\n\n  \n", @basic_schema)
  end