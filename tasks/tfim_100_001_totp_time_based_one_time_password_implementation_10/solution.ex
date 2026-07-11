  test "valid? rejects a wrong code" do
    secret = TOTP.generate_secret()
    now = :os.system_time(:second)
    code = TOTP.generate_code(secret, now)

    wrong =
      code
      |> String.to_integer()
      |> then(&rem(&1 + 1, 1_000_000))
      |> Integer.to_string()
      |> String.pad_leading(6, "0")

    refute TOTP.valid?(secret, wrong, time: now)
  end