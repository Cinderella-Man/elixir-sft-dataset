  test "TeamStore.list_members returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.list_members(store, "nope")
  end