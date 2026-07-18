  test "start_link honors the :name option and the API works by name" do
    name = :role_registry_named_server
    {:ok, _pid} = RoleRegistry.start_link(name: name)

    assert RoleRegistry.add_role(name, :viewer) == :ok
    assert RoleRegistry.add_role(name, :editor) == :ok
    assert RoleRegistry.grant(name, :viewer, :posts, :read) == :ok
    assert RoleRegistry.add_inheritance(name, :editor, :viewer) == :ok
    assert RoleRegistry.can?(name, :editor, :posts, :read)
    refute RoleRegistry.can?(name, :editor, :posts, :write)
  end