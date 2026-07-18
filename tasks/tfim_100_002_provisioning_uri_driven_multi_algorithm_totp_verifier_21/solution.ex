  test "6-digit codes are the truncation of the same counter" do
    config = config!(secret: @sha1_secret)
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "005924"
    assert AuthenticatorURI.code_at(config, 59) == "287082"
  end