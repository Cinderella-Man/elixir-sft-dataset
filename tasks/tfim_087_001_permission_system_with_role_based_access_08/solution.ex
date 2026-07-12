    test "can create posts" do
      assert Permissions.can?(:editor, :posts, :create, @rules)
    end