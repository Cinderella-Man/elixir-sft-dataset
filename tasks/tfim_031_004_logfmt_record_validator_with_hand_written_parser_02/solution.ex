  test "validates fully valid logfmt records" do
    input = """
    level=info host=web01 method=GET duration=42 success=true
    level=error host=web02 method=POST duration=150 success=false
    """

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [first, second] = valid
    assert first["level"] == "info"
    assert first["host"] == "web01"
    assert first["duration"] == "42"
    assert second["success"] == "false"
  end