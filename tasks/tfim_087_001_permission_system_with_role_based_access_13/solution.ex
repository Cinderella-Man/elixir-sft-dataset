    test "can read posts (inherited)" do
      assert Permissions.can?(:manager, :posts, :read, @rules)
    end