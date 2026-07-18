  test "TeamStore.decline_invite clears invitation without adding member", %{store: store} do
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert {:ok, "dave"} = TeamStore.decline_invite(store, "team-1", "dave")
    refute TeamStore.is_member?(store, "team-1", "dave")
    refute TeamStore.is_invited?(store, "team-1", "dave")
  end