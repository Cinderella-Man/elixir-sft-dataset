  test "register returns a base32 secret", %{vault: v} do
    assert {:ok, secret} = TOTPVault.register(v, "alice")
    assert String.match?(secret, ~r/\A[A-Z2-7]+\z/)
  end