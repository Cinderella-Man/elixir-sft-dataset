  test "masks sensitive keys in a flat map", %{m: m} do
    result = LogMasker.mask(m, %{username: "alice", password: "s3cr3t"})
    assert result.username == "alice"
    assert result.password == "[MASKED]"
  end