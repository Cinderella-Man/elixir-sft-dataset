  test "recursively masks nested maps", %{s: s} do
    result = MaskingServer.mask(s, %{user: %{name: "carol", password: "deep"}})
    assert result.user.name == "carol"
    assert result.user.password == "[MASKED]"
  end