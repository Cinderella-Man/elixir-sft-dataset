  test "parse rejects an empty or malformed label" do
    assert AuthenticatorURI.parse("otpauth://totp/?secret=#{@sha1_secret}") ==
             {:error, :missing_label}

    assert AuthenticatorURI.parse("otpauth://totp/Acme:?secret=#{@sha1_secret}") ==
             {:error, :missing_label}

    assert AuthenticatorURI.parse("otpauth://totp/:alice?secret=#{@sha1_secret}") ==
             {:error, :missing_label}
  end