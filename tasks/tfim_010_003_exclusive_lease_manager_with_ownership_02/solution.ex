  test "acquire grants a lease on an available resource", %{mgr: mgr} do
    assert {:ok, lease_id} = LeaseManager.acquire(mgr, :printer, :alice)
    assert is_binary(lease_id)
  end