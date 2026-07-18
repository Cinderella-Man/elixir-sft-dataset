  test "a single record can produce multiple errors" do
    # missing level, bad duration, bad success
    input = "host=web01 method=GET duration=abc success=yes\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(errors) >= 3
  end