  test "parse rejects a missing secret" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?issuer=Acme") ==
             {:error, :missing_secret}
  end