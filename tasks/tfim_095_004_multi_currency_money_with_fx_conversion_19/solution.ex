  test "total/3 rounds each conversion independently" do
    # Two 100 USD -> EUR each round to 91, total 182 (not round(200*1.0/1.10)=182 here, same)
    result = Money.total([Money.new(100, :USD), Money.new(100, :USD)], :EUR, @rates)
    assert result.amount == 182
  end