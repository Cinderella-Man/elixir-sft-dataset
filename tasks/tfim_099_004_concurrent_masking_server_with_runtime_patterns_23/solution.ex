  test "masks an unseparated credit card", %{s: s} do
    assert MaskingServer.mask_string(s, "4111111111111234") == "************1234"
  end