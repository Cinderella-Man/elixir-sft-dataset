  test "TeamStore.accept_invite adds member and clears invitation", %{store: store} do
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert {:ok, "dave"} = TeamStore.accept_invite(store, "team-1", "dave")
    assert TeamStore.is_member?(store, "team-1", "dave")
    refute TeamStore.is_invited?(store, "team-1", "dave")
  end