  test "sensitive key matching is case-insensitive for string and atom keys", %{s: s} do
    result = MaskingServer.mask(s, %{"PASSWORD" => "x", "Token" => "y", User: "z"})
    assert result["PASSWORD"] == "[MASKED]"
    assert result["Token"] == "[MASKED]"
    assert result[:User] == "z"
    assert MaskingServer.stats(s).keys_masked == 2
  end