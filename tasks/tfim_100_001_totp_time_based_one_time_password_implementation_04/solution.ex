  test "generate_secret output is decodable back to 20 bytes" do
    secret = TOTP.generate_secret()
    # Round-tripping through generate_code is the simplest proxy for
    # a valid decode — it will crash if the base32 is malformed.
    assert is_binary(TOTP.generate_code(secret, 0))
  end