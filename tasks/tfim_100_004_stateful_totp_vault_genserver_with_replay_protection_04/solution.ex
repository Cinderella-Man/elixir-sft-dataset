  test "secret returns :not_found for an unknown account", %{vault: v} do
    assert {:error, :not_found} = TOTPVault.secret(v, "nobody")
  end