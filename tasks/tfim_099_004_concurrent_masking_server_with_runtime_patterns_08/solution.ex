  test "masks a dashed credit card", %{s: s} do
    assert MaskingServer.mask_string(s, "4111-1111-1111-1234") == "****-****-****-1234"
  end