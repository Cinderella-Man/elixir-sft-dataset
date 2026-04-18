defmodule PermissionsTest do
  use ExUnit.Case, async: true

  # ---------------------------------------------------------------------------
  # Shared rules fixture
  # ---------------------------------------------------------------------------

  @rules %{
    posts: %{
      read: :viewer,
      create: :editor,
      update: :editor,
      delete: :manager,
      publish: :admin
    },
    settings: %{
      read: :manager,
      update: :admin
    },
    profile: %{
      read: :viewer,
      update: :owner
    }
  }

  # ---------------------------------------------------------------------------
  # Viewer permissions
  # ---------------------------------------------------------------------------

  describe "viewer role" do
    test "can read posts" do
      assert Permissions.can?(:viewer, :posts, :read, @rules)
    end

    test "cannot create posts" do
      refute Permissions.can?(:viewer, :posts, :create, @rules)
    end

    test "cannot delete posts" do
      refute Permissions.can?(:viewer, :posts, :delete, @rules)
    end

    test "cannot read settings" do
      refute Permissions.can?(:viewer, :settings, :read, @rules)
    end

    test "cannot publish posts" do
      refute Permissions.can?(:viewer, :posts, :publish, @rules)
    end
  end

  # ---------------------------------------------------------------------------
  # Editor permissions
  # ---------------------------------------------------------------------------

  describe "editor role" do
    test "can read posts (inherited from viewer)" do
      assert Permissions.can?(:editor, :posts, :read, @rules)
    end

    test "can create posts" do
      assert Permissions.can?(:editor, :posts, :create, @rules)
    end

    test "can update posts" do
      assert Permissions.can?(:editor, :posts, :update, @rules)
    end

    test "cannot delete posts" do
      refute Permissions.can?(:editor, :posts, :delete, @rules)
    end

    test "cannot publish posts" do
      refute Permissions.can?(:editor, :posts, :publish, @rules)
    end

    test "cannot read settings" do
      refute Permissions.can?(:editor, :settings, :read, @rules)
    end
  end

  # ---------------------------------------------------------------------------
  # Manager permissions
  # ---------------------------------------------------------------------------

  describe "manager role" do
    test "can read posts (inherited)" do
      assert Permissions.can?(:manager, :posts, :read, @rules)
    end

    test "can create and update posts (inherited)" do
      assert Permissions.can?(:manager, :posts, :create, @rules)
      assert Permissions.can?(:manager, :posts, :update, @rules)
    end

    test "can delete posts" do
      assert Permissions.can?(:manager, :posts, :delete, @rules)
    end

    test "cannot publish posts" do
      refute Permissions.can?(:manager, :posts, :publish, @rules)
    end

    test "can read settings" do
      assert Permissions.can?(:manager, :settings, :read, @rules)
    end

    test "cannot update settings" do
      refute Permissions.can?(:manager, :settings, :update, @rules)
    end
  end

  # ---------------------------------------------------------------------------
  # Admin permissions
  # ---------------------------------------------------------------------------

  describe "admin role" do
    test "can do everything on posts" do
      for action <- [:read, :create, :update, :delete, :publish] do
        assert Permissions.can?(:admin, :posts, action, @rules),
               "expected admin to be able to #{action} posts"
      end
    end

    test "can read and update settings" do
      assert Permissions.can?(:admin, :settings, :read, @rules)
      assert Permissions.can?(:admin, :settings, :update, @rules)
    end
  end

  # ---------------------------------------------------------------------------
  # :owner special case
  # ---------------------------------------------------------------------------

  describe ":owner permission" do
    test "grants access when user_id matches owner_id" do
      assert Permissions.can?(:viewer, :profile, :update, @rules,
               user_id: 42,
               owner_id: 42
             )
    end

    test "denies access when user_id does not match owner_id" do
      refute Permissions.can?(:viewer, :profile, :update, @rules,
               user_id: 1,
               owner_id: 99
             )
    end

    test "denies access when no owner opts are provided" do
      refute Permissions.can?(:viewer, :profile, :update, @rules)
    end

    test "admin is still denied when ids do not match (owner is identity-based, not role-based)" do
      refute Permissions.can?(:admin, :profile, :update, @rules,
               user_id: 1,
               owner_id: 99
             )
    end

    test "admin is granted when ids match" do
      assert Permissions.can?(:admin, :profile, :update, @rules,
               user_id: 7,
               owner_id: 7
             )
    end
  end

  # ---------------------------------------------------------------------------
  # Unknown resource / action
  # ---------------------------------------------------------------------------

  describe "unknown resource or action" do
    test "returns false for unknown resource" do
      refute Permissions.can?(:admin, :nonexistent, :read, @rules)
    end

    test "returns false for unknown action on known resource" do
      refute Permissions.can?(:admin, :posts, :nonexistent_action, @rules)
    end
  end

  # ---------------------------------------------------------------------------
  # Role hierarchy completeness
  # ---------------------------------------------------------------------------

  describe "role hierarchy is strictly ordered" do
    # For every role pair (lower, higher), if lower can do X then higher can too
    # (for non-owner rules)
    @hierarchy [:viewer, :editor, :manager, :admin]

    test "every role can do at least what all roles below it can do" do
      non_owner_rules =
        for {res, actions} <- @rules,
            {act, req} <- actions,
            req != :owner,
            into: %{},
            do: {{res, act}, req}

      for i <- 0..(length(@hierarchy) - 2) do
        lower = Enum.at(@hierarchy, i)
        higher = Enum.at(@hierarchy, i + 1)

        for {{res, act}, _req} <- non_owner_rules do
          if Permissions.can?(lower, res, act, @rules) do
            assert Permissions.can?(higher, res, act, @rules),
                   "#{higher} should be able to #{act} #{res} because #{lower} can"
          end
        end
      end
    end
  end
end
