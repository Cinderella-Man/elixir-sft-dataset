  test "role_of returns error for non-member", %{store: store} do
    assert :error = TeamStore.role_of(store, "team-1", "carol")
  end