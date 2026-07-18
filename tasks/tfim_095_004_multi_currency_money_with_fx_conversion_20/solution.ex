  test "total/3 with a single already-target-currency element" do
    result = Money.total([Money.new(55, :GBP)], :GBP, @rates)
    assert result.amount == 55
  end