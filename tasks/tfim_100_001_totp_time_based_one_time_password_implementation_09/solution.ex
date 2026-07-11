  test "valid? accepts the current code" do
    secret = TOTP.generate_secret()
    now = :os.system_time(:second)
    code = TOTP.generate_code(secret, now)
    assert TOTP.valid?(secret, code, time: now)
  end