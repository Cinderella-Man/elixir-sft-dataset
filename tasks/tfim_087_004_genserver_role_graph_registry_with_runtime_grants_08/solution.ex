    test "transitive inheritance across a chain", %{server: s} do
      for r <- [:viewer, :editor, :manager], do: RoleRegistry.add_role(s, r)
      RoleRegistry.grant(s, :viewer, :posts, :read)
      RoleRegistry.grant(s, :editor, :posts, :write)
      RoleRegistry.add_inheritance(s, :editor, :viewer)
      RoleRegistry.add_inheritance(s, :manager, :editor)

      assert RoleRegistry.can?(s, :manager, :posts, :read)
      assert RoleRegistry.can?(s, :manager, :posts, :write)
    end