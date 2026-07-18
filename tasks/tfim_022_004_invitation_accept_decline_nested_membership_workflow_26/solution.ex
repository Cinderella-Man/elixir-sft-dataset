  test "TeamStore.invite_member returns conflict for an existing member", %{store: store} do
    assert {:error, :conflict} = TeamStore.invite_member(store, "team-1", "alice")
  end