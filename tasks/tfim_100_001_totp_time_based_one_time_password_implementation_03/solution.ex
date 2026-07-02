  test "generate_secret returns different secrets each call" do
    secrets = for _ <- 1..20, do: TOTP.generate_secret()
    assert Enum.uniq(secrets) == secrets
  end