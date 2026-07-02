  test "generate_secret returns a non-empty base32 string" do
    secret = TOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) > 0
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end