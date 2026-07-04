  test "holder returns :available for unknown resource", %{mgr: mgr} do
    assert {:error, :available} = LeaseManager.holder(mgr, :printer)
  end