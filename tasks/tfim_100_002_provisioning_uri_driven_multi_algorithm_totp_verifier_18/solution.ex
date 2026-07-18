  test "parse rejects a secret that normalizes to the empty string" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=%3D%3D%3D") ==
             {:error, :invalid_secret}
  end