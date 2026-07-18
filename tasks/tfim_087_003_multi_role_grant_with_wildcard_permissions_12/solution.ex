    test "grants may themselves be wildcards" do
      principal = %{roles: [], grants: ["billing:*"]}
      assert Rbac.permitted?(principal, :billing, :refund, @roles)
      refute Rbac.permitted?(principal, :posts, :read, @roles)
    end