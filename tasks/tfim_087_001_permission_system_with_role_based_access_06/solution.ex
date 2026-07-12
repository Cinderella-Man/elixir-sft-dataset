    test "cannot publish posts" do
      refute Permissions.can?(:viewer, :posts, :publish, @rules)
    end