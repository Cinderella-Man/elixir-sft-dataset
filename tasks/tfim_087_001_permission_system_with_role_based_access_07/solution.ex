    test "can read posts (inherited from viewer)" do
      assert Permissions.can?(:editor, :posts, :read, @rules)
    end