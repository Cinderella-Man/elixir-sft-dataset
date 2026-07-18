  test "provisioning_uri with special characters in issuer and account is still valid" do
    uri = TOTP.provisioning_uri(@rfc_secret, "My Company, LLC", "user+tag@domain.io")
    parsed = URI.parse(uri)
    params = URI.decode_query(parsed.query)
    assert params["secret"] == @rfc_secret
    assert params["digits"] == "6"
    assert params["period"] == "30"
  end