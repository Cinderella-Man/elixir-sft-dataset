  test "TeamStore.get_version returns not_found for unknown team", %{store: store} do
    assert {:error, :not_found} = TeamStore.get_version(store, "nope")
  end