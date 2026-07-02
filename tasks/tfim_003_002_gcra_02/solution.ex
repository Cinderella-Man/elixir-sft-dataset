  test "a brand-new bucket admits the configured burst back-to-back", %{gl: gl} do
    # 5 req/sec, burst of 5 — should admit 5 instantly
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end