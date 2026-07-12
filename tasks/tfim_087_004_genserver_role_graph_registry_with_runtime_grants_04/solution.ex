    test "add_role is idempotent", %{server: s} do
      assert RoleRegistry.add_role(s, :viewer) == :ok
      assert RoleRegistry.add_role(s, :viewer) == :ok
    end