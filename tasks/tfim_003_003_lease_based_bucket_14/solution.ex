  test "active_leases returns 0 for unknown bucket", %{lb: lb} do
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "never_seen")
  end