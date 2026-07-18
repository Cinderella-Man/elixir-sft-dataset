  test "valid? with window: 0 only accepts the exact current step" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_current = TOTP.generate_code(secret, now)
    code_prev = TOTP.generate_code(secret, now - 30)

    assert TOTP.valid?(secret, code_current, time: now, window: 0)
    refute TOTP.valid?(secret, code_prev, time: now, window: 0)
  end