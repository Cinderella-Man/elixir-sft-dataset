  test "parse percent-decodes the label" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme%20Co:alice%40example.com?secret=#{@sha1_secret}"
             )

    assert config.issuer == "Acme Co"
    assert config.account == "alice@example.com"
  end