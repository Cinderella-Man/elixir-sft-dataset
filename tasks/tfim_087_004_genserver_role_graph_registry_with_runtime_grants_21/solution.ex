  test "revoke on an unknown role returns ok without creating the role", %{server: s} do
    assert RoleRegistry.revoke(s, :ghost, :posts, :read) == :ok
    refute RoleRegistry.can?(s, :ghost, :posts, :read)
    assert RoleRegistry.grant(s, :ghost, :posts, :read) == {:error, :unknown_role}
  end