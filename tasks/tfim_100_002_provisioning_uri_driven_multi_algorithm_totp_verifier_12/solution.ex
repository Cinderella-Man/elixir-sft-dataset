  test "parse rejects a non-otpauth scheme" do
    assert AuthenticatorURI.parse("https://totp/Acme:alice?secret=#{@sha1_secret}") ==
             {:error, :invalid_scheme}
  end