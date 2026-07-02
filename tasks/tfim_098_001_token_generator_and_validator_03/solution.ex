  test "payload is preserved exactly through round-trip" do
    payload = %{role: "admin", sub: "user:99", meta: [1, 2, 3]}
    token = generate(payload, "my-secret", 60)
    assert {:ok, ^payload} = verify(token, "my-secret")
  end