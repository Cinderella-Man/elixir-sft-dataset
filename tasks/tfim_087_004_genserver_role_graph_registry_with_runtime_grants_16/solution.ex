  test "rejected cycle edge is not recorded at all", %{server: s} do
    RoleRegistry.add_role(s, :a)
    RoleRegistry.add_role(s, :b)
    assert RoleRegistry.add_inheritance(s, :a, :b) == :ok
    assert RoleRegistry.add_inheritance(s, :b, :a) == {:error, :cycle}

    RoleRegistry.grant(s, :a, :res, :act)
    # the rejected b -> a edge must not exist, so b must not inherit a's grant
    refute RoleRegistry.can?(s, :b, :res, :act)

    RoleRegistry.grant(s, :b, :other, :act)
    # the accepted a -> b edge must survive the rejection unchanged
    assert RoleRegistry.can?(s, :a, :other, :act)
  end