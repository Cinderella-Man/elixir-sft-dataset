    test "action wildcard (*:read)" do
      roles = %{auditor: ["*:read"]}
      assert Rbac.permitted?([:auditor], :posts, :read, roles)
      assert Rbac.permitted?([:auditor], :settings, :read, roles)
      refute Rbac.permitted?([:auditor], :posts, :write, roles)
    end