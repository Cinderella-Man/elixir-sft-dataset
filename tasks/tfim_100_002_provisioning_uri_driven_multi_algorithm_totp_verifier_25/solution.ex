  test "a different period yields a different counter" do
    p30 = config!(secret: @sha1_secret)
    p60 = config!(secret: @sha1_secret, period: "60")

    # div(59, 30) == 1 while div(59, 60) == 0, so the codes come from
    # different counters.
    assert AuthenticatorURI.code_at(p30, 59) == "287082"
    assert AuthenticatorURI.code_at(p60, 59) == AuthenticatorURI.code_at(p30, 0)
  end