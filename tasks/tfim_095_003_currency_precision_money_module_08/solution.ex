  test "from_major/2 scales by the currency exponent" do
    assert Money.from_major(12.34, :USD).amount == 1234
    assert Money.from_major(500, :JPY).amount == 500
    assert Money.from_major(1.2345, :BHD).amount == 1235
  end