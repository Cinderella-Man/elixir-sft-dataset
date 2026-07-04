  test "release returns error for unknown resource", %{mgr: mgr} do
    assert {:error, :not_held} = LeaseManager.release(mgr, :scanner, :alice)
  end