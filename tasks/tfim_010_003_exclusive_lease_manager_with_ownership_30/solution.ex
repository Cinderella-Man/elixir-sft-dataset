  test "lease ids are unpadded url-safe base64 of 16 random bytes", %{mgr: mgr} do
    {:ok, id1} = LeaseManager.acquire(mgr, :printer, :alice)
    {:ok, id2} = LeaseManager.acquire(mgr, :scanner, :bob)

    assert String.length(id1) == 22
    assert id1 =~ ~r/\A[A-Za-z0-9_-]{22}\z/
    refute String.contains?(id1, "=")
    assert id1 != id2
  end