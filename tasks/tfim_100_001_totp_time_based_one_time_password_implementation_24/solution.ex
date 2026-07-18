  test "valid? accepts an integer code whose decimal form is shorter than six digits" do
    time = 1_234_567_890
    assert TOTP.generate_code(@rfc_secret, time) == "005924"

    assert TOTP.valid?(@rfc_secret, 5924, time: time, window: 0)
    refute TOTP.valid?(@rfc_secret, 5925, time: time, window: 0)
  end