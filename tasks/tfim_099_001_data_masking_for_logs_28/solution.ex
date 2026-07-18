  test "masks sensitive keys inside a list of keyword lists", %{m: m} do
    data = [
      [user: "alice", password: "pass1"],
      [user: "bob", token: "tok_xyz"]
    ]

    [r1, r2] = LogMasker.mask(m, data)
    assert r1[:user] == "alice"
    assert r1[:password] == "[MASKED]"
    assert r2[:user] == "bob"
    assert r2[:token] == "[MASKED]"
  end