  test "provisioning_uri uses the hotp type and includes the counter" do
    uri = HOTP.provisioning_uri(@secret, "Acme", "alice@example.com", 5)
    assert String.starts_with?(uri, "otpauth://hotp/")

    parsed = URI.parse(uri)
    assert parsed.scheme == "otpauth"
    assert parsed.host == "hotp"

    params = URI.decode_query(parsed.query)
    assert params["secret"] == @secret
    assert params["issuer"] == "Acme"
    assert params["algorithm"] == "SHA1"
    assert params["digits"] == "6"
    assert params["counter"] == "5"
  end