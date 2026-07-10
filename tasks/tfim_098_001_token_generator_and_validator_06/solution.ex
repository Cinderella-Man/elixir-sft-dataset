  test "expired token returns :expired" do
    token = generate("data", "s3cr3t", 100)
    Clock.advance(101)
    assert {:error, :expired} = verify(token, "s3cr3t")
  end