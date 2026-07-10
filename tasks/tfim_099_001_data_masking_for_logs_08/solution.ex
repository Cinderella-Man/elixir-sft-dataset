  test "masks sensitive keys in a list of maps", %{m: m} do
    data = [
      %{user: "alice", password: "pass1"},
      %{user: "bob", password: "pass2"}
    ]

    [r1, r2] = LogMasker.mask(m, data)
    assert r1.user == "alice"
    assert r1.password == "[MASKED]"
    assert r2.user == "bob"
    assert r2.password == "[MASKED]"
  end