  test "code length always equals the configured digit count" do
    for d <- ["6", "7", "8"] do
      config = config!(secret: @sha1_secret, digits: d)
      code = AuthenticatorURI.code_at(config, 1_234_567_890)
      assert byte_size(code) == config.digits
      assert String.match?(code, ~r/\A\d+\z/)
    end
  end