  test "built-in patterns still work after a custom pattern is added", %{s: s} do
    MaskingServer.add_pattern(s, ~r/\d{3}-\d{4}/, "[PHONE]")
    assert MaskingServer.mask_string(s, "4111-1111-1111-1234") == "****-****-****-1234"
  end