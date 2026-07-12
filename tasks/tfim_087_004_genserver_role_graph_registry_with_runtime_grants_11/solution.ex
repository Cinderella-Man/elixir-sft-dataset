    test "self edge rejected", %{server: s} do
      RoleRegistry.add_role(s, :a)
      assert RoleRegistry.add_inheritance(s, :a, :a) == {:error, :cycle}
    end