    test "cannot publish posts" do
      refute Permissions.can?(:editor, :posts, :publish, @rules)
    end