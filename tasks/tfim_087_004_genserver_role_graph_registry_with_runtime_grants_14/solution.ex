    test "revoking parent grant affects child immediately", %{server: s} do
      RoleRegistry.add_role(s, :viewer)
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.grant(s, :viewer, :posts, :read)
      RoleRegistry.add_inheritance(s, :editor, :viewer)
      assert RoleRegistry.can?(s, :editor, :posts, :read)

      RoleRegistry.revoke(s, :viewer, :posts, :read)
      refute RoleRegistry.can?(s, :editor, :posts, :read)
    end