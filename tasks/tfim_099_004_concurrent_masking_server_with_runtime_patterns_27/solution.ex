  test "space-separated cards survive a custom pattern being registered", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\bnow\b/, "[WHEN]")
    assert MaskingServer.mask_string(s, "4111 1111 1111 1234 now") == "**** **** **** 1234 [WHEN]"
  end