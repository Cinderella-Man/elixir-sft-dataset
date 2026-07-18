  test "different buckets are completely isolated", %{lb: lb} do
    {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "a", 3, 1.0, 3, 60_000)
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "a", 3, 1.0, 1, 60_000)

    # Bucket "b" is untouched
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "b", 3, 1.0, 1, 60_000)
    assert {:ok, _, 1} = LeaseBucket.acquire_lease(lb, "b", 3, 1.0, 1, 60_000)
  end