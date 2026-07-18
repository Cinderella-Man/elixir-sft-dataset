  test "seconds_remaining returns the full period on a boundary" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_110) == 30
  end