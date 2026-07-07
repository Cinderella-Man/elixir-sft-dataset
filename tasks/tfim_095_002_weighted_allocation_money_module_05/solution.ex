  test "add/2 sums same-currency values" do
    result = Money.add(Money.new(100, :USD), Money.new(250, :USD))
    assert result.amount == 350
    assert result.currency == :USD
  end