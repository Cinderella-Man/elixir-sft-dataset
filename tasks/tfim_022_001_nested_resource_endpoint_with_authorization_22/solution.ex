  test "TeamStore.add_member_safe returns conflict for duplicate", %{store: store} do
    assert {:error, :conflict} = TeamStore.add_member_safe(store, "team-1", "alice")
  end