  test "pause returns :not_found for unknown service", %{mon: mon} do
    assert {:error, :not_found} = ManagedMonitor.pause(mon, "ghost")
  end