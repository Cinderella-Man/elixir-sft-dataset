  test "TeamStore.team_exists? returns false for unknown team", %{store: store} do
    refute TeamStore.team_exists?(store, "nope")
  end