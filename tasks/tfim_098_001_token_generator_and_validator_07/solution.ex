  test "token expires exactly at ttl boundary" do
    token = generate("data", "s3cr3t", 50)
    Clock.advance(50)
    # At exactly ttl seconds the token should be expired (issued_at + ttl <= now)
    assert {:error, :expired} = verify(token, "s3cr3t")
  end