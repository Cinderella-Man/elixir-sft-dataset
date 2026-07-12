  test "parse strips a single space after the label colon" do
    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/Acme:%20alice?secret=#{@sha1_secret}")

    assert config.issuer == "Acme"
    assert config.account == "alice"
  end