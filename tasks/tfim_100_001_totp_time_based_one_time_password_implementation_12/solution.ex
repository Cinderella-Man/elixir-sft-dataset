  test "valid? accepts codes from adjacent steps within the default window" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_prev = TOTP.generate_code(secret, now - 30)
    code_next = TOTP.generate_code(secret, now + 30)

    assert TOTP.valid?(secret, code_prev, time: now, window: 1)
    assert TOTP.valid?(secret, code_next, time: now, window: 1)
  end