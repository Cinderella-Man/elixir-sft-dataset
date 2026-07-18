  test "split/2 amounts differ by at most one cent" do
    for amount <- [1, 7, 101, 1000, 9999], n <- 2..9 do
      amounts = Money.split(Money.new(amount, :USD), n) |> Enum.map(& &1.amount)

      assert Enum.max(amounts) - Enum.min(amounts) <= 1,
             "split(#{amount}, #{n}) produced uneven shares: #{inspect(amounts)}"
    end
  end