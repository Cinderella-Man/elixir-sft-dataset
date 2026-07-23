  test "masks cards at the shortest and longest documented lengths", %{s: s} do
    assert MaskingServer.mask_string(s, "4111111111234") == "*********1234"
    assert MaskingServer.mask_string(s, "1234567890123456789") == "***************6789"
  end