  test "valid records are returned as maps keyed by field names" do
    input = "level=info host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, "level")
    assert Map.has_key?(row, "host")
    assert Map.has_key?(row, "method")
    assert Map.has_key?(row, "duration")
    assert Map.has_key?(row, "success")
  end