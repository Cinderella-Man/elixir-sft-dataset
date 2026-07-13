  test "a live budget is not treated as spent: an instant fetch still gets collected" do
    outcomes =
      for _ <- 1..50 do
        PooledFetcher.fetch_all([{:fast, fn -> {:ok, :now} end}], 1, 1)[:fast]
      end

    assert Enum.any?(outcomes, &(&1 == {:ok, :now})),
           "an instant fetch was never collected within a live 1ms budget"
  end