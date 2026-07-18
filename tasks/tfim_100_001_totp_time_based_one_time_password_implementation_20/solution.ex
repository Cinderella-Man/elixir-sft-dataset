  test "provisioning_uri is parseable as a URI" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com")
    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "totp"
    assert parsed.query != nil
  end