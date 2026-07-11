  test "valid? accepts an integer code as well as a string code" do
    secret = TOTP.generate_secret()
    now = :os.system_time(:second)
    code_str = TOTP.generate_code(secret, now)
    code_int = String.to_integer(code_str)

    assert TOTP.valid?(secret, code_str, time: now)
    assert TOTP.valid?(secret, code_int, time: now)
  end