  test "generate_code returns a 6-character string" do
    secret = TOTP.generate_secret()
    code = TOTP.generate_code(secret, :os.system_time(:second))
    assert is_binary(code)
    assert byte_size(code) == 6
    assert String.match?(code, ~r/\A\d{6}\z/)
  end