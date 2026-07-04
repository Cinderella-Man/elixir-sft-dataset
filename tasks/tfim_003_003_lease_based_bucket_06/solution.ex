  test "release of unknown lease returns {:error, :unknown_lease}", %{lb: lb} do
    # Unknown bucket
    assert {:error, :unknown_lease} =
             LeaseBucket.release(lb, "nope", make_ref(), :cancelled)

    # Known bucket, unknown lease
    LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)

    assert {:error, :unknown_lease} =
             LeaseBucket.release(lb, "k", make_ref(), :cancelled)
  end