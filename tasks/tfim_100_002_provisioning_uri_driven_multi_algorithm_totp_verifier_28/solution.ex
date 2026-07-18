  test "seconds_remaining honours a custom period" do
    config = config!(secret: @sha1_secret, period: "60")
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_111) == 29
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_080) == 60
  end