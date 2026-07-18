  test "granting twice is idempotent so a single revoke clears it", %{server: s} do
    RoleRegistry.add_role(s, :editor)
    assert RoleRegistry.grant(s, :editor, :posts, :write) == :ok
    assert RoleRegistry.grant(s, :editor, :posts, :write) == :ok
    assert RoleRegistry.can?(s, :editor, :posts, :write)

    assert RoleRegistry.revoke(s, :editor, :posts, :write) == :ok
    refute RoleRegistry.can?(s, :editor, :posts, :write)
  end