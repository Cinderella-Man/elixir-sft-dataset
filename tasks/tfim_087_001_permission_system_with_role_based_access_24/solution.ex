    test "admin is granted when ids match" do
      assert Permissions.can?(:admin, :profile, :update, @rules,
               user_id: 7,
               owner_id: 7
             )
    end