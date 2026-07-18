  test "valid? rejects codes two steps away when window is 1" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_two_steps_ago = TOTP.generate_code(secret, now - 60)
    code_two_steps_ahead = TOTP.generate_code(secret, now + 60)

    refute TOTP.valid?(secret, code_two_steps_ago, time: now, window: 1)
    refute TOTP.valid?(secret, code_two_steps_ahead, time: now, window: 1)
  end