    test "denies access when no owner opts are provided" do
      refute Permissions.can?(:viewer, :profile, :update, @rules)
    end