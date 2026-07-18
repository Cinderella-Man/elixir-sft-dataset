  test "valid integer passes" do
    input = "level=info host=web01 method=GET duration=42 success=true\n"
    assert {:ok, [_], []} = LogfmtValidator.validate_string(input, @basic_schema)
  end