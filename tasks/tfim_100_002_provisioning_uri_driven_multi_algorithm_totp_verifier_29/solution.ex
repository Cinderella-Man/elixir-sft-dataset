  test "verify accepts the code for the current step" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.verify(config, "005924", 1_234_567_890)
    assert AuthenticatorURI.verify(config, AuthenticatorURI.code_at(config, 59), 59)
  end