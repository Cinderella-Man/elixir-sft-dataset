  test "token is valid just before expiry" do
    token = generate("data", "s3cr3t", 100)
    Clock.advance(99)
    assert {:ok, "data"} = verify(token, "s3cr3t")
  end