  test "parse rejects the hotp type" do
    assert AuthenticatorURI.parse("otpauth://hotp/Acme:alice?secret=#{@sha1_secret}&counter=1") ==
             {:error, :unsupported_type}
  end