  test "optional field that is missing does NOT produce an error" do
    schema = [field("level"), field("tag", required: false)]
    input = "level=info\n"

    assert {:ok, [_row], []} = LogfmtValidator.validate_string(input, schema)
  end