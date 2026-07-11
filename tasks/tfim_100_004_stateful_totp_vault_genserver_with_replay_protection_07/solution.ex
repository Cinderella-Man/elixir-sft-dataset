  test "current_code returns :not_found for unknown account", %{vault: v} do
    assert {:error, :not_found} = TOTPVault.current_code(v, "ghost", time: 1)
  end