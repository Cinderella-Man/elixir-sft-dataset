    test "grants access when user_id matches owner_id" do
      assert Permissions.can?(:viewer, :profile, :update, @rules,
               user_id: 42,
               owner_id: 42
             )
    end