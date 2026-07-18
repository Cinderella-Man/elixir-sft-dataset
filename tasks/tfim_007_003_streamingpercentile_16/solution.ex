  test "different stream names are independent", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 10)
    for v <- 100..110, do: StreamingPercentile.push(s, "b", v, 11)

    {:ok, a_med} = StreamingPercentile.percentile(s, "a", 0.5)
    {:ok, b_med} = StreamingPercentile.percentile(s, "b", 0.5)

    assert close_to(a_med, 5.5)
    assert close_to(b_med, 105.0)

    # Pushing to "a" doesn't affect "b"
    StreamingPercentile.push(s, "a", 99999, 10)
    {:ok, b_med_again} = StreamingPercentile.percentile(s, "b", 0.5)
    assert close_to(b_med, b_med_again)
  end