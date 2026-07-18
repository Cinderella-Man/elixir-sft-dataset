  test "ipv4 format rejects invalid addresses" do
    schema = [field("ip", format: :ipv4)]
    input = "ip=999.999.999.999\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, schema)
    assert {1, "ip", msg} = hd(errors)
    assert msg =~ "format"
  end