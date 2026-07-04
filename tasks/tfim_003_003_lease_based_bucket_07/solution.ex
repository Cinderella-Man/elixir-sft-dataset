  test "double-release returns {:error, :unknown_lease} on second call", %{lb: lb} do
    {:ok, lease_id, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 2, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :cancelled)
    assert {:error, :unknown_lease} = LeaseBucket.release(lb, "k", lease_id, :cancelled)
  end