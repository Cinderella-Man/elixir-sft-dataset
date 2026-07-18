  test "split/2 always sums back to the original amount" do
    for amount <- [0, 1, 2, 5, 7, 10, 99, 100, 101, 333, 1000, 9999, 12_345],
        n <- 1..13 do
      parts = Money.split(Money.new(amount, :USD), n)
      assert length(parts) == n

      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount,
             "split(#{amount}, #{n}) did not sum back to #{amount}"

      assert Enum.all?(parts, &(&1.currency == :USD))
    end
  end