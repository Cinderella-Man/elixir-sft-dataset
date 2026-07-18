  test "split/2 gives the extra minor unit to the first Integer.mod/2 parties for any sign" do
    # Shares are the floored base, with one extra minor unit handed to each of
    # the first `Integer.mod(amount, n)` parties -- so they always sum back,
    # for negative amounts just as much as for positive ones.
    amounts = [-12_345, -1000, -101, -100, -7, -5, -2, -1, 0, 1, 5, 7, 101, 1000]

    for amount <- amounts, n <- 1..9 do
      shares = Money.split(Money.new(amount, :USD), n) |> Enum.map(& &1.amount)

      base = Integer.floor_div(amount, n)
      remainder = Integer.mod(amount, n)
      expected = Enum.map(0..(n - 1), fn i -> if i < remainder, do: base + 1, else: base end)

      assert length(shares) == n
      assert shares == expected
      assert Enum.sum(shares) == amount
    end
  end