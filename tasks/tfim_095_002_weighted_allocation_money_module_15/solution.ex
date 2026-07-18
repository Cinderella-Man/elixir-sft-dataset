  test "allocate/2 returns exactly one struct per weight" do
    assert length(Money.allocate(Money.new(1000, :USD), [1, 2, 3, 4, 5])) == 5
  end