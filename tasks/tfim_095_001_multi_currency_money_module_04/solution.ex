  test "new/2 allows zero" do
    assert Money.new(0, :JPY).amount == 0
  end