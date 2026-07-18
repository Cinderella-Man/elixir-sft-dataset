  test "unknown role alongside a known role keeps the known role's permissions" do
    principal = [:viewer, :ghost]

    assert Rbac.effective_permissions(principal, @roles) ==
             MapSet.new(["posts:read", "comments:read"])

    assert Rbac.permitted?(principal, :posts, :read, @roles)
    refute Rbac.permitted?(principal, :posts, :write, @roles)
  end