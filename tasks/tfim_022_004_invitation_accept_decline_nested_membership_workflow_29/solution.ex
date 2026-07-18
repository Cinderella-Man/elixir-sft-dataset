  test "TeamStore.is_invited? reflects a pending invitation", %{store: store} do
    refute TeamStore.is_invited?(store, "team-1", "dave")
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert TeamStore.is_invited?(store, "team-1", "dave")
  end