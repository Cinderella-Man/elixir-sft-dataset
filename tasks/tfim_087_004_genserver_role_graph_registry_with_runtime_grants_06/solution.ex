    test "revoke of missing grant is ok", %{server: s} do
      RoleRegistry.add_role(s, :editor)
      assert RoleRegistry.revoke(s, :editor, :posts, :write) == :ok
    end