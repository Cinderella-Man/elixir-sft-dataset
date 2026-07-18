  test "force_release returns :ok for unknown resource", %{mgr: mgr} do
    assert :ok = LeaseManager.force_release(mgr, :printer)
  end