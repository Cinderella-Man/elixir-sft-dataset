    test "cannot create posts" do
      refute Permissions.can?(:viewer, :posts, :create, @rules)
    end