    test "can delete posts" do
      assert Permissions.can?(:manager, :posts, :delete, @rules)
    end