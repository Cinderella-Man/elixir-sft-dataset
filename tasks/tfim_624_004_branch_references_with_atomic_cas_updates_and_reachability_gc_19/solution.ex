  test "list_branches is empty for a fresh store", %{store: s} do
    assert ObjectStore.list_branches(s) == %{}
  end