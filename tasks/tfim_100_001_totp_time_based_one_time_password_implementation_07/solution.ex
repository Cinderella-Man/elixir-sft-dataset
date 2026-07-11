  test "same code is produced for all timestamps within the same 30-second step" do
    secret = TOTP.generate_secret()
    base_time = 90_000

    code_at_start = TOTP.generate_code(secret, base_time)

    for offset <- 1..29 do
      assert TOTP.generate_code(secret, base_time + offset) == code_at_start,
             "Code differed at offset +#{offset}"
    end
  end