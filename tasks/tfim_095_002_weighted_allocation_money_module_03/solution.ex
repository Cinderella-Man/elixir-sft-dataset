  test "new/2 allows negative amounts and zero" do
    assert Money.new(-250, :EUR).amount == -250
    assert Money.new(0, :JPY).amount == 0
  end