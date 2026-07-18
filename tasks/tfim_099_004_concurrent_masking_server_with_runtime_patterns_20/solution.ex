  test "custom patterns are applied in registration order", %{s: s} do
    assert MaskingServer.add_pattern(s, ~r/alpha/, "beta") == :ok
    assert MaskingServer.add_pattern(s, ~r/beta/, "gamma") == :ok
    assert MaskingServer.mask_string(s, "alpha") == "gamma"
  end