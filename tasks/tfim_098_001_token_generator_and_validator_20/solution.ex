  test "non-binary token or non-binary secret returns :malformed" do
    assert {:error, :malformed} = verify(nil, "secret")
    assert {:error, :malformed} = verify(12_345, "secret")
    assert {:error, :malformed} = verify(:not_a_token, "secret")
    assert {:error, :malformed} = verify(["list"], "secret")

    token = generate("data", "secret", 300)
    assert {:error, :malformed} = verify(token, :not_a_secret)
    assert {:error, :malformed} = verify(token, 999)
  end