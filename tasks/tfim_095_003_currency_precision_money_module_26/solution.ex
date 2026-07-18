  test "from_major/2 rounds negative halves away from zero" do
    assert Money.from_major(-0.005, :USD).amount == -1
    assert Money.from_major(-1.2345, :BHD).amount == -1235
    assert is_integer(Money.from_major(-0.005, :USD).amount)
  end