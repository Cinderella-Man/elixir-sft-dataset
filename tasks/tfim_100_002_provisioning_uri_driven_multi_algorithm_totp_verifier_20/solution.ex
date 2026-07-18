  test "parse accepts a non-default period" do
    assert config!(secret: @sha1_secret, period: "90").period == 90
  end