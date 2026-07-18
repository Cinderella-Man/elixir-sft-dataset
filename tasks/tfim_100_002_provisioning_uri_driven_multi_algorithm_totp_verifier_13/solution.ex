  test "parse rejects a non-binary argument" do
    assert AuthenticatorURI.parse(nil) == {:error, :invalid_scheme}
    assert AuthenticatorURI.parse(:otpauth) == {:error, :invalid_scheme}
  end