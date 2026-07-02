  test "new/2 builds a struct with amount and currency" do
    m = Money.new(100, :USD)
    assert m.amount == 100
    assert m.currency == :USD
  end