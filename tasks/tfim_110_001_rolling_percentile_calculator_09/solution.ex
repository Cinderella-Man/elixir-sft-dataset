  test "reset clears a series" do
    start_server([])

    for v <- 1..10, do: Percentile.record(:r, v)
    assert {:ok, _} = Percentile.query(:r, 0.5)

    assert :ok = Percentile.reset(:r)
    assert {:error, :empty} = Percentile.query(:r, 0.5)

    # can be reused after reset
    Percentile.record(:r, 7)
    assert {:ok, 7} = Percentile.query(:r, 0.5)
  end