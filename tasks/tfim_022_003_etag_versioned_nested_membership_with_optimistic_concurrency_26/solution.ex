  test "TeamStore.add_member_safe returns stale on version mismatch", %{store: store} do
    assert {:error, :stale} = TeamStore.add_member_safe(store, "team-1", "carol", 999)
  end