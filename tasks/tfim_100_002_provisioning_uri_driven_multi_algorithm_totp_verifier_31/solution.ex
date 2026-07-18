  test "verify rejects a wrong code" do
    config = config!(secret: @sha1_secret)
    refute AuthenticatorURI.verify(config, "999999", 1_234_567_890)
    refute AuthenticatorURI.verify(config, "12345", 1_234_567_890)
  end