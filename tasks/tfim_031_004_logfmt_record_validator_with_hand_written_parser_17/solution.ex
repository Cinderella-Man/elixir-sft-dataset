  test "invalid float produces a type error" do
    schema = [field("latency", type: :float)]
    input = "latency=notfloat\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, schema)
    assert {1, "latency", msg} = hd(errors)
    assert msg =~ "float"
  end