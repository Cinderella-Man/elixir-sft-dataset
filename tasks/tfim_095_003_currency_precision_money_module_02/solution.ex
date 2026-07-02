  test "exponent/1 returns the right precision per currency" do
    assert Money.exponent(:USD) == 2
    assert Money.exponent(:JPY) == 0
    assert Money.exponent(:BHD) == 3
    assert Money.exponent(:KWD) == 3
  end