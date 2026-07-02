  test "new/2 allows negative amounts (debts)" do
    m = Money.new(-250, :EUR)
    assert m.amount == -250
    assert m.currency == :EUR
  end