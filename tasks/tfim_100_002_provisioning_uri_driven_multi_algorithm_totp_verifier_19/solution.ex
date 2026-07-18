  test "parse rejects an unsupported algorithm" do
    assert AuthenticatorURI.parse(
             "otpauth://totp/Acme:alice?secret=#{@sha1_secret}&algorithm=MD5"
           ) == {:error, :unsupported_algorithm}
  end