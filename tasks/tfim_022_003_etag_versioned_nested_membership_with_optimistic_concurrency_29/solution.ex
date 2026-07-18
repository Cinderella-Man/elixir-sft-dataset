  test "TeamStore.add_member_safe returns ok with new version on success", %{store: store} do
    v = version(store, "team-2")
    assert {:ok, "dave", nv} = TeamStore.add_member_safe(store, "team-2", "dave", v)
    assert nv == v + 1
  end