    test "can read posts" do
      assert Permissions.can?(:viewer, :posts, :read, @rules)
    end