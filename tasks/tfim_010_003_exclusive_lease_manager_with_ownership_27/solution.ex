  test "various resource and owner types", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, "string_resource", {:tuple, :owner})
    {:ok, _} = LeaseManager.acquire(mgr, 42, "string_owner")
    {:ok, _} = LeaseManager.acquire(mgr, {:complex, :key}, :atom_owner)

    assert {:ok, {:tuple, :owner}, _} = LeaseManager.holder(mgr, "string_resource")
    assert {:ok, "string_owner", _} = LeaseManager.holder(mgr, 42)
    assert {:ok, :atom_owner, _} = LeaseManager.holder(mgr, {:complex, :key})
  end