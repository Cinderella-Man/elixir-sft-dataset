  test "valid? with no time option uses the real clock" do
    secret = TOTP.generate_secret()
    code = TOTP.generate_code(secret, :os.system_time(:second))
    assert TOTP.valid?(secret, code)
  end