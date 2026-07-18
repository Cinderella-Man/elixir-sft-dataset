  test "allocate/2 always sums back to the original amount" do
    for amount <- [0, 1, 7, 100, 101, 999, 12_345, -50, -333],
        ratios <- [[1], [1, 1], [1, 2, 3], [5, 1, 1], [2, 2, 2, 2], [1, 3, 5, 7]] do
      parts = Money.allocate(Money.new(amount, :USD), ratios)
      assert length(parts) == length(ratios)

      assert Enum.sum(Enum.map(parts, & &1.amount)) == amount,
             "allocate(#{amount}, #{inspect(ratios)}) did not sum back"
    end
  end