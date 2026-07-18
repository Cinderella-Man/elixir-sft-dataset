  test "verify accepts an integer code, zero-padding it" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.verify(config, 5924, 1_234_567_890)
  end