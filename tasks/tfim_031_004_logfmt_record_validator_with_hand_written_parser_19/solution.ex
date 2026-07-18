  test "invalid boolean produces a type error" do
    input = "level=info host=web01 method=GET duration=42 success=yes\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "success", msg} = find_error(errors, 1, "success")
    assert msg =~ "boolean"
  end