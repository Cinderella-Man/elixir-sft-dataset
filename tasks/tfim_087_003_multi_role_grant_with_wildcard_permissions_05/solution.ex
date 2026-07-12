    test "combines permissions of all held roles" do
      principal = [:viewer, :moderator]
      assert Rbac.permitted?(principal, :posts, :read, @roles)
      assert Rbac.permitted?(principal, :comments, :delete, @roles)
      refute Rbac.permitted?(principal, :posts, :write, @roles)
    end