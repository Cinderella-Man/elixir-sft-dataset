  test "provisioning_uri encodes special characters in the label" do
    uri = HOTP.provisioning_uri(@secret, "Acme Co", "user+tag@domain.io", 0)
    assert uri =~ "Acme%20Co:user%2Btag%40domain.io"
    params = URI.decode_query(URI.parse(uri).query)
    assert params["counter"] == "0"
  end