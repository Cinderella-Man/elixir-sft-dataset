  test "generate_code is deterministic for a given counter" do
    secret = HOTP.generate_secret()
    assert HOTP.generate_code(secret, 7) == HOTP.generate_code(secret, 7)
  end