  test "bare keys (no = sign) are treated as boolean flags with value true" do
    schema = [field("verbose", type: :boolean), field("level")]
    input = "verbose level=info\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["verbose"] == "true"
  end