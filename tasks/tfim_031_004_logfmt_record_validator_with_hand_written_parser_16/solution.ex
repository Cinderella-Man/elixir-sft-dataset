  test "float field accepts decimal strings" do
    schema = [field("latency", type: :float)]
    input = "latency=3.14\n"
    assert {:ok, [_], []} = LogfmtValidator.validate_string(input, schema)
  end