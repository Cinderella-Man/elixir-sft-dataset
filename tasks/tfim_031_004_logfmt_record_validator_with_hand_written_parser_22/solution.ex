  test "custom regex format works" do
    schema = [field("code", format: ~r/^[A-Z]{3}-\d{3}$/)]
    input = "code=ABC-123\ncode=abc-123\ncode=TOOLONG-1234\n"

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, schema)
    assert length(valid) == 1
    assert length(errors) == 2
    assert hd(valid)["code"] == "ABC-123"
  end