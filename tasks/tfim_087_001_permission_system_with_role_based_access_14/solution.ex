    test "can create and update posts (inherited)" do
      assert Permissions.can?(:manager, :posts, :create, @rules)
      assert Permissions.can?(:manager, :posts, :update, @rules)
    end