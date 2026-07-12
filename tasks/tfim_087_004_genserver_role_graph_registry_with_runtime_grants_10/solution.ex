    test "unknown roles rejected", %{server: s} do
      RoleRegistry.add_role(s, :editor)
      assert RoleRegistry.add_inheritance(s, :editor, :nope) == {:error, :unknown_role}
      assert RoleRegistry.add_inheritance(s, :nope, :editor) == {:error, :unknown_role}
    end