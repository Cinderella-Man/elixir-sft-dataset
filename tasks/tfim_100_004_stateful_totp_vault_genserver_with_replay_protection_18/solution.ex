  test "a fresh secret encodes 160 bits: exactly 32 unpadded base32 characters", %{vault: v} do
    {:ok, secret} = TOTPVault.register(v, "alice")
    assert String.match?(secret, ~r/\A[A-Z2-7]{32}\z/)
  end