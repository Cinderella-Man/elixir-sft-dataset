  test "masks a 15-digit card with uneven hyphen groups", %{s: s} do
    assert MaskingServer.mask_string(s, "3782-822463-10005") == "****-******-*0005"
  end