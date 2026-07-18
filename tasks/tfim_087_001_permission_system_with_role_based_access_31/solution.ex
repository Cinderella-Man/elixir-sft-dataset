  test "unknown resource or action returns false even when owner opts are supplied" do
    refute Permissions.can?(:admin, :nonexistent, :read, @rules, user_id: 1, owner_id: 1)

    refute Permissions.can?(:admin, :profile, :nonexistent_action, @rules,
             user_id: 1,
             owner_id: 1
           )

    refute Permissions.can?(:viewer, :nonexistent, :update, @rules, user_id: 2, owner_id: 2)
    refute Permissions.can?(:admin, :posts, :archive, @rules)
  end