  test "BOM characters at start are stripped" do
    input = "\xEF\xBB\xBF" <> "level=info host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, @basic_schema)
    assert row["level"] == "info"
  end