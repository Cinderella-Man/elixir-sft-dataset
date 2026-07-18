  test "seconds_remaining counts down within a period" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_111) == 29
    assert AuthenticatorURI.seconds_remaining(config, 1_111_111_139) == 1
  end