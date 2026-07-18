  test "branch_head returns no_branch for unknown branch", %{store: s} do
    assert {:error, :no_branch} = ObjectStore.branch_head(s, "missing")
  end