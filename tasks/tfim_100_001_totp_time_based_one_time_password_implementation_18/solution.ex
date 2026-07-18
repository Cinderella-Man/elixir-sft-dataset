  test "provisioning_uri contains the correct label" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme Co", "alice@example.com")
    assert uri =~ "Acme%20Co:alice%40example.com" or uri =~ "Acme+Co:alice%40example.com"
  end