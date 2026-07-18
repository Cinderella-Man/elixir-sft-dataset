  test "TeamStore.is_member? returns false for non-member", %{store: store} do
    refute TeamStore.is_member?(store, "team-1", "carol")
  end