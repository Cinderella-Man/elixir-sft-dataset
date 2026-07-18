    test "direct back-edge rejected", %{server: s} do
      RoleRegistry.add_role(s, :a)
      RoleRegistry.add_role(s, :b)
      assert RoleRegistry.add_inheritance(s, :a, :b) == :ok
      assert RoleRegistry.add_inheritance(s, :b, :a) == {:error, :cycle}
    end