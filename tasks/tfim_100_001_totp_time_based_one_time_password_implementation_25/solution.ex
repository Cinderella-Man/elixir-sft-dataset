  test "provisioning_uri label decodes back to issuer colon account_name" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme Co", "alice@example.com")
    parsed = URI.parse(uri)

    label =
      parsed.path
      |> String.trim_leading("/")
      |> URI.decode()

    assert label == "Acme Co:alice@example.com"

    params = URI.decode_query(parsed.query)
    assert params["issuer"] == "Acme Co"
    assert params["algorithm"] == "SHA1"
  end