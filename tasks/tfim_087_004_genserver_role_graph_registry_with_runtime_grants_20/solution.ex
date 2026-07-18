  test "revoking from a child leaves the inherited grant intact", %{server: s} do
    RoleRegistry.add_role(s, :viewer)
    RoleRegistry.add_role(s, :editor)
    RoleRegistry.grant(s, :viewer, :posts, :read)
    RoleRegistry.add_inheritance(s, :editor, :viewer)
    assert RoleRegistry.can?(s, :editor, :posts, :read)

    # editor has no direct grant here; revoking must not touch viewer's grant
    assert RoleRegistry.revoke(s, :editor, :posts, :read) == :ok
    assert RoleRegistry.can?(s, :viewer, :posts, :read)
    assert RoleRegistry.can?(s, :editor, :posts, :read)
  end