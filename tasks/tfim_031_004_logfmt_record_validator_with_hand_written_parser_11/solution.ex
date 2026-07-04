  test "required field with empty value produces an error" do
    input = "level= host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "level", msg} = find_error(errors, 1, "level")
    assert msg =~ "required"
  end