  test "matching owner opts do not grant role-gated actions the role cannot perform" do
    refute Permissions.can?(:viewer, :posts, :delete, @rules, user_id: 5, owner_id: 5)
    refute Permissions.can?(:editor, :posts, :publish, @rules, user_id: 5, owner_id: 5)
    refute Permissions.can?(:manager, :settings, :update, @rules, user_id: 5, owner_id: 5)
  end