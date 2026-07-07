  test "new/2 allows negatives and zero" do
    assert Money.new(-5, :USD).amount == -5
    assert Money.new(0, :JPY).amount == 0
  end