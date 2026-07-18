  test "split/2 floors for negative amounts so shares still sum back" do
    parts = Money.split(Money.new(-5, :USD), 2)
    assert Enum.map(parts, & &1.amount) == [-2, -3]

    for amount <- [-1, -7, -100, -101, -999, -12_345], n <- 1..9 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount
    end
  end