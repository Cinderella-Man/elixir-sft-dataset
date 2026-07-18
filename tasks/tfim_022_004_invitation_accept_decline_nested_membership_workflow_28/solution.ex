  test "TeamStore.invite_member returns not_found for a missing team", %{store: store} do
    assert {:error, :not_found} = TeamStore.invite_member(store, "nope", "dave")
  end