  test "masks a space-separated card inside a map value", %{s: s} do
    result = MaskingServer.mask(s, %{note: "card 4111 1111 1111 1234 on file"})
    assert result.note == "card **** **** **** 1234 on file"
  end