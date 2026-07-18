  test "boolean field accepts true, false, 1, 0 case-insensitively" do
    schema = [field("flag", type: :boolean)]

    lines = ["flag=TRUE", "flag=False", "flag=0", "flag=1"]
    input = Enum.join(lines, "\n")

    assert {:ok, valid, []} = LogfmtValidator.validate_string(input, schema)
    assert length(valid) == 4
  end