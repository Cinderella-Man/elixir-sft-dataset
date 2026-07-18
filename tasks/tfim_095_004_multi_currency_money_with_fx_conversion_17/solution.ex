  test "total/3 converts each and sums into the target currency" do
    result = Money.total([Money.new(100, :USD), Money.new(100, :EUR)], :USD, @rates)
    assert result.amount == 210
    assert result.currency == :USD
  end