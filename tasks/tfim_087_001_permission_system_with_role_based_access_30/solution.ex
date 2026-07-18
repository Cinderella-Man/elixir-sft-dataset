  test "role comparison ignores owner opts for non-owner rules" do
    assert Permissions.can?(:admin, :settings, :update, @rules, user_id: 1, owner_id: 99)
    assert Permissions.can?(:editor, :posts, :create, @rules, user_id: 1, owner_id: 99)
    assert Permissions.can?(:manager, :posts, :delete, @rules, user_id: nil, owner_id: nil)
    refute Permissions.can?(:viewer, :settings, :read, @rules, user_id: 3, owner_id: 3)
  end