  test "different buckets maintain independent TATs", %{gl: gl} do
    for _ <- 1..5, do: GcraLimiter.acquire(gl, "a", 5.0, 5)
    assert {:error, :rate_exceeded, _} = GcraLimiter.acquire(gl, "a", 5.0, 5)

    # Bucket "b" has not been touched
    assert {:ok, 4} = GcraLimiter.acquire(gl, "b", 5.0, 5)
    assert {:ok, 3} = GcraLimiter.acquire(gl, "b", 5.0, 5)
  end