  test "renew returns error for unknown resource", %{mgr: mgr} do
    assert {:error, :not_held} = LeaseManager.renew(mgr, :scanner, :alice)
  end