    test "viewer can read posts but not write" do
      assert Rbac.permitted?([:viewer], :posts, :read, @roles)
      refute Rbac.permitted?([:viewer], :posts, :write, @roles)
    end