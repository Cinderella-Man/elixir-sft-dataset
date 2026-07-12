    test "grants add to role permissions" do
      principal = %{roles: [:viewer], grants: ["reports:export"]}
      assert Rbac.permitted?(principal, :posts, :read, @roles)
      assert Rbac.permitted?(principal, :reports, :export, @roles)
      refute Rbac.permitted?(principal, :posts, :write, @roles)
    end