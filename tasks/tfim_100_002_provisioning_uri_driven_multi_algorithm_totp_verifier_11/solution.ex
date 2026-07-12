  test "parse accepts digits 6, 7 and 8" do
    assert config!(secret: @sha1_secret, digits: "6").digits == 6
    assert config!(secret: @sha1_secret, digits: "7").digits == 7
    assert config!(secret: @sha1_secret, digits: "8").digits == 8
  end