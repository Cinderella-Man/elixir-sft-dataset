  test "sources that finished before the kill report their real outcome" do
    # Fifty instant sources with a quorum of one: dozens complete before the
    # post-quorum shutdown sweep, and each such reply is sitting in the
    # mailbox — those sources "had already succeeded" and may not be
    # blanket-cancelled.
    sources = for i <- 1..50, do: {:"s#{i}", fn -> {:ok, i} end}

    results = QuorumFetcher.fetch_first(sources, 1, 5_000)

    ok_count = Enum.count(results, fn {_name, r} -> match?({:ok, _}, r) end)
    assert ok_count >= 2
  end