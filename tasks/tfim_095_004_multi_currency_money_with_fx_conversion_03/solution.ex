  test "new/2 allows negatives and zero" do
    assert Money.new(-250, :EUR).amount == -250
    assert Money.new(0, :GBP).amount == 0
  end