  test "wrong secret returns :invalid_signature" do
    token = generate("payload", "correct-secret", 300)
    assert {:error, :invalid_signature} = verify(token, "wrong-secret")
  end