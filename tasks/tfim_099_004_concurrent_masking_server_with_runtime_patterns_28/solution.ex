  test "stats counts one pattern per card regardless of separator style", %{s: s} do
    MaskingServer.mask_string(s, "4111 1111 1111 1234")
    MaskingServer.mask_string(s, "4111111111234")
    assert MaskingServer.stats(s).patterns_applied == 2
  end