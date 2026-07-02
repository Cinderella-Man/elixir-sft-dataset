  test "acquire returns error when resource is already held", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :already_held, :alice} = LeaseManager.acquire(mgr, :printer, :bob)
  end