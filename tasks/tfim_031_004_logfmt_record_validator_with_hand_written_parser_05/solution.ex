  test "quoted values with escaped quotes are parsed correctly" do
    schema = [field("msg")]
    input = ~s(msg="he said \\"hi\\""\n)

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["msg"] == ~s(he said "hi")
  end