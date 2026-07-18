  test "split/2 always sums back to the original amount" do
    for amount <- [0, 1, 7, 100, 101, 999, 12_345], n <- 1..9 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount
    end
  end