    test "can do everything on posts" do
      for action <- [:read, :create, :update, :delete, :publish] do
        assert Permissions.can?(:admin, :posts, action, @rules),
               "expected admin to be able to #{action} posts"
      end
    end