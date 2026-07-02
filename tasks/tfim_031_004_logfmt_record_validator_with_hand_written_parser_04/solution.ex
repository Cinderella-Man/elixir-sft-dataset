  test "quoted values with spaces are parsed correctly" do
    schema = [field("msg"), field("level")]
    input = ~s(level=info msg="hello world"\n)

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["msg"] == "hello world"
  end