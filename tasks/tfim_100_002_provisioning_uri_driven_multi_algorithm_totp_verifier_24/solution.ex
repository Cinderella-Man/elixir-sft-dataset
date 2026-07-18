  test "code is stable across a period and changes at the boundary" do
    config = config!(secret: @sha1_secret)

    assert AuthenticatorURI.code_at(config, 1_111_111_111) ==
             AuthenticatorURI.code_at(config, 1_111_111_139)

    refute AuthenticatorURI.code_at(config, 1_111_111_109) ==
             AuthenticatorURI.code_at(config, 1_111_111_111)
  end