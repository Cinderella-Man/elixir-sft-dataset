  test "extra keys not in schema are silently ignored" do
    input = "level=info host=web01 method=GET duration=42 success=true extra=stuff another=42\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, @basic_schema)
    assert row["level"] == "info"
    refute Map.has_key?(row, "extra")
    refute Map.has_key?(row, "another")
  end