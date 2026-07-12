    test "resource wildcard (comments:*)" do
      assert Rbac.permitted?([:moderator], :comments, :read, @roles)
      assert Rbac.permitted?([:moderator], :comments, :ban, @roles)
      refute Rbac.permitted?([:moderator], :posts, :read, @roles)
    end