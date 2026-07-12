  test "generate_code returns a 6-character numeric string" do
    secret = HOTP.generate_secret()
    code = HOTP.generate_code(secret, 42)
    assert byte_size(code) == 6
    assert Regex.match?(~r/\A\d{6}\z/, code)
  end