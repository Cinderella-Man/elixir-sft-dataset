  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = seal(payload, @key, 60)
    assert {:ok, ^payload} = open(token, @key)
  end