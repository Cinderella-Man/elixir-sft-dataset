  test "stats counts keys_masked across mask calls", %{s: s} do
    MaskingServer.mask(s, %{password: "a", token: "b"})
    MaskingServer.mask(s, %{password: "c"})
    assert MaskingServer.stats(s).keys_masked == 3
  end