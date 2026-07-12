  test "generate_secret returns a 32-character base32 string" do
    secret = HOTP.generate_secret()
    assert is_binary(secret)
    assert byte_size(secret) == 32
    assert Regex.match?(~r/\A[A-Z2-7]+\z/, secret)
  end