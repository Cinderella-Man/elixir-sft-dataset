  test "map principal with only :grants key defaults roles to empty and honors grants" do
    principal = %{grants: ["reports:export"]}
    assert Rbac.permitted?(principal, :reports, :export, @roles)
    refute Rbac.permitted?(principal, :posts, :read, @roles)
    assert Rbac.effective_permissions(principal, @roles) == MapSet.new(["reports:export"])
  end