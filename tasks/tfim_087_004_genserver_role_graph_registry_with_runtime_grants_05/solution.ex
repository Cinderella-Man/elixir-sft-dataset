    test "revoke removes only that grant", %{server: s} do
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.grant(s, :editor, :posts, :write)
      RoleRegistry.grant(s, :editor, :posts, :read)
      assert RoleRegistry.revoke(s, :editor, :posts, :write) == :ok
      refute RoleRegistry.can?(s, :editor, :posts, :write)
      assert RoleRegistry.can?(s, :editor, :posts, :read)
    end