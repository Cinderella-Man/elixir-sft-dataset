  test "register is idempotent-guarded: second call errors and keeps the secret", %{vault: v} do
    assert {:ok, secret} = TOTPVault.register(v, "alice")
    assert {:error, :already_registered} = TOTPVault.register(v, "alice")
    assert {:ok, ^secret} = TOTPVault.secret(v, "alice")
  end