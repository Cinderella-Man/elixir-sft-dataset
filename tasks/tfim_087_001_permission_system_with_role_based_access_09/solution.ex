    test "can update posts" do
      assert Permissions.can?(:editor, :posts, :update, @rules)
    end