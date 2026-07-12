    test "cannot delete posts" do
      refute Permissions.can?(:editor, :posts, :delete, @rules)
    end