  test "parse rejects a secret with non-base32 characters" do
    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=ABC1DEF") ==
             {:error, :invalid_secret}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=ABC%21DEF") ==
             {:error, :invalid_secret}
  end