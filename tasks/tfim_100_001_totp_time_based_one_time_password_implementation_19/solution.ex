  test "provisioning_uri contains all required query parameters" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com")
    assert uri =~ "secret=#{@rfc_secret}"
    assert uri =~ "issuer=Acme"
    assert uri =~ "algorithm=SHA1"
    assert uri =~ "digits=6"
    assert uri =~ "period=30"
  end