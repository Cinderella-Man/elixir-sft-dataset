  test "case-insensitive key matching for string keys", %{m: m} do
    result = LogMasker.mask(m, %{"Password" => "secret", "TOKEN" => "abc"})
    assert result["Password"] == "[MASKED]"
    assert result["TOKEN"] == "[MASKED]"
  end