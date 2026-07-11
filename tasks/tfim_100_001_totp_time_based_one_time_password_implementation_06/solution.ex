  test "generate_code zero-pads codes shorter than 6 digits" do
    # We can't force a specific short code without a known secret, but
    # we can verify the RFC vector at t=59 which starts with "28" (not
    # a leading-zero case) and at t=1_234_567_890 which is "005924".
    assert TOTP.generate_code(@rfc_secret, 1_234_567_890) == "005924"
  end