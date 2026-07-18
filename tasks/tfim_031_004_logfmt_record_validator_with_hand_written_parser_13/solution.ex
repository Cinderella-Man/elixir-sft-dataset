  test "invalid integer produces a type error" do
    input = "level=info host=web01 method=GET duration=abc success=true\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "duration", msg} = find_error(errors, 1, "duration")
    assert msg =~ "integer"
  end