  test "masks an SSN", %{s: s} do
    result = MaskingServer.mask_string(s, "SSN: 123-45-6789")
    assert result =~ "***-**-****"
    refute result =~ "123-45-6789"
  end