  test "TeamStore.invite_member returns already_invited on duplicate", %{store: store} do
    assert {:ok, "dave"} = TeamStore.invite_member(store, "team-1", "dave")
    assert {:error, :already_invited} = TeamStore.invite_member(store, "team-1", "dave")
  end