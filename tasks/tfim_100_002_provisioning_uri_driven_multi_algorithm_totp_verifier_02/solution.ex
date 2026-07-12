  test "parse returns a full config map" do
    assert {:ok, config} =
             AuthenticatorURI.parse(
               "otpauth://totp/Acme:alice@example.com?secret=#{@sha1_secret}&algorithm=SHA256&digits=8&period=60"
             )

    assert config == %{
             issuer: "Acme",
             account: "alice@example.com",
             secret: @sha1_secret,
             algorithm: :sha256,
             digits: 8,
             period: 60
           }
  end