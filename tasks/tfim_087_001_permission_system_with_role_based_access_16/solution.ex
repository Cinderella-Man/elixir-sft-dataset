    test "cannot publish posts" do
      refute Permissions.can?(:manager, :posts, :publish, @rules)
    end