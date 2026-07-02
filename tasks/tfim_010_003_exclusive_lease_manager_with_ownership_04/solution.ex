  test "acquire is not idempotent — same owner re-acquiring returns error", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :printer, :alice)

    assert {:error, :already_held, :alice} = LeaseManager.acquire(mgr, :printer, :alice)
  end