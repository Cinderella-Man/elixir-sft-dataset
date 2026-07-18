  test "a freshly created team has no members and version 0", %{store: store} do
    :ok = TeamStore.create_team(store, "team-fresh")

    assert {:ok, 0} = TeamStore.get_version(store, "team-fresh")
    assert {:ok, []} = TeamStore.list_members(store, "team-fresh")
  end