  test "parse takes the issuer from the query param when the label has none" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/alice@example.com?secret=#{@sha1_secret}&issuer=Acme"
             )

    assert config.issuer == "Acme"
    assert config.account == "alice@example.com"
  end