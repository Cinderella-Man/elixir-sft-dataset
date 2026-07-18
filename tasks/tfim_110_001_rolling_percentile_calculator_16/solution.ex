  test "all samples expiring reports empty" do
    start_server(window_ms: 500)

    for v <- 1..20, do: Percentile.record(:t, v)
    assert {:ok, _} = Percentile.query(:t, 0.5)

    Clock.advance(500)
    assert {:error, :empty} = Percentile.query(:t, 0.5)
  end