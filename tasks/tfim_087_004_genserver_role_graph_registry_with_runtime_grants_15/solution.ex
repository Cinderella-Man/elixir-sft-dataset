    test "granting parent later flows to child", %{server: s} do
      RoleRegistry.add_role(s, :viewer)
      RoleRegistry.add_role(s, :editor)
      RoleRegistry.add_inheritance(s, :editor, :viewer)
      refute RoleRegistry.can?(s, :editor, :settings, :read)

      RoleRegistry.grant(s, :viewer, :settings, :read)
      assert RoleRegistry.can?(s, :editor, :settings, :read)
    end