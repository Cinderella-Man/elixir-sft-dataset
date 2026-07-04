  test "consuming multiple tokens at once deducts all of them", %{gl: gl} do
    # Burst of 5; take 3 in one call
    assert {:ok, 2} = GcraLimiter.acquire(gl, "k", 5.0, 5, 3)

    # Only 2 single-token acquires left in the burst
    assert {:ok, 1} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:ok, 0} = GcraLimiter.acquire(gl, "k", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "k", 5.0, 5)
  end