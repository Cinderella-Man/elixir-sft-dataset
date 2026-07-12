    test "unknown role grants nothing" do
      refute Rbac.permitted?([:ghost], :posts, :read, @roles)
      assert Rbac.effective_permissions([:ghost], @roles) == MapSet.new()
    end