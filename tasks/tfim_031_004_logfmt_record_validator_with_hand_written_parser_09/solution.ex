  test "unterminated quote produces a malformed line error" do
    input = ~s(level=info msg="unterminated\n)

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "_line", msg} = hd(errors)
    assert msg =~ "malformed"
  end