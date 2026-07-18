  test "fresh server starts with no roles, no edges and no grants" do
    {:ok, s} = RoleRegistry.start_link()

    refute RoleRegistry.can?(s, :editor, :posts, :read)
    assert RoleRegistry.grant(s, :editor, :posts, :read) == {:error, :unknown_role}
    assert RoleRegistry.add_inheritance(s, :editor, :viewer) == {:error, :unknown_role}

    # after adding the roles there must still be no pre-existing edges or grants
    RoleRegistry.add_role(s, :viewer)
    RoleRegistry.add_role(s, :editor)
    RoleRegistry.grant(s, :viewer, :posts, :read)
    refute RoleRegistry.can?(s, :editor, :posts, :read)
  end