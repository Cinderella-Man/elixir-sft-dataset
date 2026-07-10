  test "masks sensitive keys in a flat map", %{s: s} do
    result = MaskingServer.mask(s, %{user: "alice", password: "hunter2"})
    assert result.user == "alice"
    assert result.password == "[MASKED]"
  end