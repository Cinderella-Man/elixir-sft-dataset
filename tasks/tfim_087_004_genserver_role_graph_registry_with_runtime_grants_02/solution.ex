    test "grant then can?", %{server: s} do
      assert RoleRegistry.add_role(s, :editor) == :ok
      assert RoleRegistry.grant(s, :editor, :posts, :write) == :ok
      assert RoleRegistry.can?(s, :editor, :posts, :write)
      refute RoleRegistry.can?(s, :editor, :posts, :delete)
    end