  test "parse applies defaults for algorithm, digits and period" do
    config = config!(secret: @sha1_secret)
    assert config.algorithm == :sha1
    assert config.digits == 6
    assert config.period == 30
  end