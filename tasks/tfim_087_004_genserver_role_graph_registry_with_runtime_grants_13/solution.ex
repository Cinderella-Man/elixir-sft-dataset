    test "transitive cycle rejected and state unchanged", %{server: s} do
      for r <- [:a, :b, :c], do: RoleRegistry.add_role(s, r)
      RoleRegistry.grant(s, :a, :res, :act)
      RoleRegistry.add_inheritance(s, :b, :a)
      RoleRegistry.add_inheritance(s, :c, :b)
      # c -> b -> a already; adding a -> c would close a cycle
      assert RoleRegistry.add_inheritance(s, :a, :c) == {:error, :cycle}
      # state unchanged: c still inherits a's grant
      assert RoleRegistry.can?(s, :c, :res, :act)
    end