  test "parse accepts a matching issuer in both label and query param" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme%20Co:alice?secret=#{@sha1_secret}&issuer=Acme+Co"
             )

    assert config.issuer == "Acme Co"
  end