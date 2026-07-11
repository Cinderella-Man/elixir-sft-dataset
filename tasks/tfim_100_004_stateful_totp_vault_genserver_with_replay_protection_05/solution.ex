  test "different accounts get different secrets", %{vault: v} do
    {:ok, a} = TOTPVault.register(v, "alice")
    {:ok, b} = TOTPVault.register(v, "bob")
    refute a == b
  end