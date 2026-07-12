    test "cannot delete posts" do
      refute Permissions.can?(:viewer, :posts, :delete, @rules)
    end