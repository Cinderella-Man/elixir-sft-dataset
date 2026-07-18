  test "total/3 of an empty list is zero in the target currency" do
    result = Money.total([], :EUR, @rates)
    assert result.amount == 0
    assert result.currency == :EUR
  end