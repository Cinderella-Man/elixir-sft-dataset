  test "masks string-keyed sensitive fields", %{m: m} do
    result = LogMasker.mask(m, %{"token" => "abc123", "name" => "Bob"})
    assert result["token"] == "[MASKED]"
    assert result["name"] == "Bob"
  end