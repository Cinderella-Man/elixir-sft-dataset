  test "retry_after actually elapses to an admitted request", %{hl: hl} do
    wide = [{:t, 5, 1_000}]

    # Fill the shared timestamp list with 5 staggered entries (t = 0,100,..,400).
    assert {:ok, %{t: 4}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 3}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 2}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 1}} = HierarchicalLimiter.check(hl, "k", wide)
    Clock.advance(100)
    assert {:ok, %{t: 0}} = HierarchicalLimiter.check(hl, "k", wide)

    # Same shared list, now evaluated against a tighter cap of 2 (4 entries over).
    narrow = [{:t, 2, 1_000}]

    assert {:error, :rate_limited, :t, retry} =
             HierarchicalLimiter.check(hl, "k", narrow)

    # The contract fixes retry as the wait until this tier admits a new request.
    # After exactly that wait the tier must accept — waiting only for the single
    # oldest entry to expire (retry = 600) leaves the tier still saturated.
    Clock.advance(retry)
    assert {:ok, _} = HierarchicalLimiter.check(hl, "k", narrow)
  end