  test "exponent/1 knows every currency in the table, including EUR and GBP" do
    assert Money.exponent(:EUR) == 2
    assert Money.exponent(:GBP) == 2
    assert Money.from_major(123.45, :EUR).amount == 12_345
    assert Money.to_string(Money.new(12_345, :GBP)) == "123.45 GBP"
  end