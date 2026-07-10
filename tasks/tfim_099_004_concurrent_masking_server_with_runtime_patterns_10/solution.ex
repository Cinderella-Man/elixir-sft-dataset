  test "a registered custom pattern is applied during mask_string", %{s: s} do
    assert MaskingServer.add_pattern(s, ~r/\d{3}-\d{4}/, "[PHONE]") == :ok
    assert MaskingServer.mask_string(s, "call 555-1234 now") == "call [PHONE] now"
  end