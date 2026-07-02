  test "status returns :not_found for unregistered service", %{mon: mon} do
    assert {:error, :not_found} = RateMonitor.status(mon, "ghost")
  end