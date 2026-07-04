  test "multi-token acquire that exceeds burst is rejected", %{gl: gl} do
    # Burst of 5; asking for 6 at once must be rejected
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5, 6)

    # And rejection must not have mutated TAT — the full burst is still available
    assert {:ok, 4} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end