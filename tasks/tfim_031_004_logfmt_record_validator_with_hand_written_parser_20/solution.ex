  test "ipv4 format accepts valid addresses" do
    schema = [field("ip", format: :ipv4)]
    input = "ip=192.168.1.1\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["ip"] == "192.168.1.1"
  end