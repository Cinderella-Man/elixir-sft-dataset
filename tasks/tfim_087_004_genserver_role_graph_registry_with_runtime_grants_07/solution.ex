    test "child inherits parent permissions", %{server: s} do
      RoleRegistry.add_role(s, :viewer)
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.grant(s, :viewer, :posts, :read)
      assert RoleRegistry.add_inheritance(s, :editor, :viewer) == :ok

      assert RoleRegistry.can?(s, :editor, :posts, :read)
      refute RoleRegistry.can?(s, :viewer, :posts, :write)
    end