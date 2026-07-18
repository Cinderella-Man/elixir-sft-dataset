  test "float field accepts integer-formatted strings" do
    schema = [field("latency", type: :float)]
    input = "latency=42\n"
    assert {:ok, [_], []} = LogfmtValidator.validate_string(input, schema)
  end