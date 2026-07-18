  test "provisioning_uri starts with otpauth://totp/" do
    uri = TOTP.provisioning_uri(@rfc_secret, "Acme", "alice@example.com")
    assert String.starts_with?(uri, "otpauth://totp/")
  end