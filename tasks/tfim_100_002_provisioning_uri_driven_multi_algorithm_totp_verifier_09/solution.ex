  test "parse normalizes a lowercase, padded, whitespace-y secret" do
    raw = String.downcase(@sha1_secret) <> "===="

    assert {:ok, config} =
             AuthenticatorURI.parse("otpauth://totp/Acme:alice?secret=#{URI.encode(raw)}")

    assert config.secret == @sha1_secret
  end