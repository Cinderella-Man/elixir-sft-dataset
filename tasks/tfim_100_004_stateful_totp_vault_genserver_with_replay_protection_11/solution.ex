  test "consume returns :not_found for an unknown account", %{vault: v} do
    assert TOTPVault.consume(v, "ghost", "123456", time: 90_000) == {:error, :not_found}
  end