    test "diamond inheritance (multiple parents)", %{server: s} do
      for r <- [:base, :left, :right, :top], do: RoleRegistry.add_role(s, r)
      RoleRegistry.grant(s, :left, :a, :x)
      RoleRegistry.grant(s, :right, :b, :y)
      RoleRegistry.add_inheritance(s, :top, :left)
      RoleRegistry.add_inheritance(s, :top, :right)

      assert RoleRegistry.can?(s, :top, :a, :x)
      assert RoleRegistry.can?(s, :top, :b, :y)
    end