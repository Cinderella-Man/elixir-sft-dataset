  test "duplicate keys — last occurrence wins" do
    schema = [field("level")]
    input = "level=info level=error\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["level"] == "error"
  end