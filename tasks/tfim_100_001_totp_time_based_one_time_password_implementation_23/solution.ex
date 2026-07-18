  test "valid? without a window option tolerates exactly one step of drift in each direction" do
    secret = TOTP.generate_secret()
    now = 90_000

    assert TOTP.valid?(secret, TOTP.generate_code(secret, now - 30), time: now)
    assert TOTP.valid?(secret, TOTP.generate_code(secret, now + 30), time: now)
    refute TOTP.valid?(secret, TOTP.generate_code(secret, now - 60), time: now)
    refute TOTP.valid?(secret, TOTP.generate_code(secret, now + 60), time: now)
  end