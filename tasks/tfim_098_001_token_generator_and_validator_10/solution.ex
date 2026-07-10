  test "signature check takes precedence over expiry check" do
    # Generate a token that is already expired
    token = generate("old", "secret", 1)
    Clock.advance(200)

    # Even though it's expired, a wrong secret should give :invalid_signature
    assert {:error, :invalid_signature} = verify(token, "bad-secret")
  end