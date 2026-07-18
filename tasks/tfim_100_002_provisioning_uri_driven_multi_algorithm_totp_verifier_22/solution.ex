  test "7-digit codes are the truncation of the same counter" do
    config = config!(secret: @sha1_secret, digits: "7")
    assert AuthenticatorURI.code_at(config, 1_234_567_890) == "9005924"
    assert AuthenticatorURI.code_at(config, 59) == "4287082"
  end