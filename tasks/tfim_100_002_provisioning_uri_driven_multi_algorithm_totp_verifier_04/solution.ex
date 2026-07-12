  test "parse accepts a label with no issuer and no issuer param" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/alice@example.com?secret=#{@sha1_secret}")

    assert config.issuer == nil
    assert config.account == "alice@example.com"
  end