  test "empty role list principal is denied everything" do
    assert Rbac.effective_permissions([], @roles) == MapSet.new()
    refute Rbac.permitted?([], :posts, :read, @roles)
    refute Rbac.permitted?(%{roles: [], grants: []}, :posts, :read, @roles)
  end