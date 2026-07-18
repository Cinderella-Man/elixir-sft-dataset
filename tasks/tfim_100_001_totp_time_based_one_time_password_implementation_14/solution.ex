  test "valid? accepts a wider window when configured" do
    secret = TOTP.generate_secret()
    now = 90_000

    code_two_steps_ago = TOTP.generate_code(secret, now - 60)
    assert TOTP.valid?(secret, code_two_steps_ago, time: now, window: 2)
  end