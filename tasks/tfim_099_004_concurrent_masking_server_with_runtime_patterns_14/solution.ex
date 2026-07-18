  test "stats counts patterns_applied across string scrubs", %{s: s} do
    MaskingServer.mask_string(s, "a@b.com and 123-45-6789")
    assert MaskingServer.stats(s).patterns_applied == 2
  end