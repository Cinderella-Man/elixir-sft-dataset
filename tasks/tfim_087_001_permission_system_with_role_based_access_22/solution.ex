    test "denies access when user_id does not match owner_id" do
      refute Permissions.can?(:viewer, :profile, :update, @rules,
               user_id: 1,
               owner_id: 99
             )
    end