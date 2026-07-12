    test "unknown role can?/grant", %{server: s} do
      refute RoleRegistry.can?(s, :ghost, :posts, :read)
      assert RoleRegistry.grant(s, :ghost, :posts, :read) == {:error, :unknown_role}
    end