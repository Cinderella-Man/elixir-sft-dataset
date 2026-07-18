  test "owner-gated action coexists with role-gated action on the same resource" do
    # profile.read is :viewer, profile.update is :owner
    assert Permissions.can?(:viewer, :profile, :read, @rules)
    refute Permissions.can?(:viewer, :profile, :update, @rules)

    assert Permissions.can?(:viewer, :profile, :read, @rules, user_id: 1, owner_id: 99)
    assert Permissions.can?(:viewer, :profile, :update, @rules, user_id: 1, owner_id: 1)
    refute Permissions.can?(:viewer, :profile, :update, @rules, user_id: 1, owner_id: 99)
  end