defmodule AccessPolicyTest do
  use ExUnit.Case, async: false

  @policies [
    %{effect: :allow, roles: :any, resource: :posts, action: :read},
    %{effect: :allow, roles: [:editor, :admin], resource: :posts, action: :write},
    %{effect: :deny, roles: [:editor], resource: :posts, action: :delete},
    %{effect: :allow, roles: [:admin], resource: :any, action: :any},
    %{effect: :deny, roles: :any, resource: :settings, action: :delete}
  ]

  describe "basic matching" do
    test "allows when a matching allow statement exists" do
      assert AccessPolicy.authorized?(:viewer, :posts, :read, @policies)
    end

    test "default-denies when nothing matches" do
      refute AccessPolicy.authorized?(:viewer, :posts, :write, @policies)
      assert AccessPolicy.evaluate(:viewer, :posts, :write, @policies) == :deny
    end

    test "list membership in roles field" do
      assert AccessPolicy.authorized?(:editor, :posts, :write, @policies)
      assert AccessPolicy.authorized?(:admin, :posts, :write, @policies)
    end
  end

  describe "explicit-deny precedence" do
    test "deny overrides a would-be allow" do
      # editor delete: matched by deny statement, no allow -> deny
      refute AccessPolicy.authorized?(:editor, :posts, :delete, @policies)
    end

    test "deny overrides a wildcard admin allow" do
      # admin :any/:any allows, but settings:delete deny wins
      assert AccessPolicy.authorized?(:admin, :settings, :read, @policies)
      refute AccessPolicy.authorized?(:admin, :settings, :delete, @policies)
    end

    test "order of statements does not matter" do
      reversed = Enum.reverse(@policies)

      assert AccessPolicy.evaluate(:admin, :settings, :delete, @policies) ==
               AccessPolicy.evaluate(:admin, :settings, :delete, reversed)

      assert AccessPolicy.evaluate(:admin, :settings, :delete, reversed) == :deny
    end
  end

  describe "wildcard :any semantics" do
    test "admin wildcard allow grants unrelated resources" do
      assert AccessPolicy.authorized?(:admin, :posts, :delete, @policies)
      assert AccessPolicy.authorized?(:admin, :reports, :export, @policies)
    end

    test ":any roles matches every role" do
      for role <- [:viewer, :editor, :manager, :admin] do
        assert AccessPolicy.authorized?(role, :posts, :read, @policies),
               "expected #{role} to read posts via :any roles"
      end
    end
  end

  describe "defaults for missing keys" do
    test "missing effect defaults to allow" do
      policies = [%{roles: [:viewer], resource: :docs, action: :read}]
      assert AccessPolicy.authorized?(:viewer, :docs, :read, policies)
    end

    test "missing roles/resource/action default to :any" do
      policies = [%{effect: :allow}]
      assert AccessPolicy.authorized?(:whoever, :whatever, :whenever, policies)
    end

    test "missing keys still respect deny precedence" do
      policies = [
        %{effect: :allow},
        %{effect: :deny, action: :delete}
      ]

      assert AccessPolicy.authorized?(:viewer, :posts, :read, policies)
      refute AccessPolicy.authorized?(:viewer, :posts, :delete, policies)
    end
  end

  describe "empty policy list" do
    test "default deny with no statements" do
      assert AccessPolicy.evaluate(:admin, :posts, :read, []) == :deny
      refute AccessPolicy.authorized?(:admin, :posts, :read, [])
    end
  end

  test "scalar role atom in :roles matches only that exact role" do
    policies = [%{effect: :allow, roles: :viewer, resource: :docs, action: :read}]

    assert AccessPolicy.evaluate(:viewer, :docs, :read, policies) == :allow
    assert AccessPolicy.evaluate(:editor, :docs, :read, policies) == :deny
  end

  test "list membership in resource field" do
    policies = [%{effect: :allow, roles: :any, resource: [:posts, :docs], action: :read}]

    assert AccessPolicy.authorized?(:viewer, :posts, :read, policies)
    assert AccessPolicy.authorized?(:viewer, :docs, :read, policies)
    refute AccessPolicy.authorized?(:viewer, :settings, :read, policies)
  end

  test "list membership in action field" do
    policies = [%{effect: :allow, roles: :any, resource: :posts, action: [:read, :write]}]

    assert AccessPolicy.authorized?(:viewer, :posts, :read, policies)
    assert AccessPolicy.authorized?(:viewer, :posts, :write, policies)
    refute AccessPolicy.authorized?(:viewer, :posts, :delete, policies)
  end

  test "authorized? returns exact booleans, never nil or other truthy values" do
    policies = [%{effect: :allow, roles: [:admin], resource: :any, action: :any}]

    assert AccessPolicy.authorized?(:admin, :posts, :read, policies) === true
    assert AccessPolicy.authorized?(:viewer, :posts, :read, policies) === false
    assert AccessPolicy.authorized?(:admin, :posts, :read, []) === false
  end

  test "deny statement with scalar roles and list resource wins over wildcard allow" do
    policies = [
      %{effect: :allow, roles: :any, resource: :any, action: :any},
      %{effect: :deny, roles: :editor, resource: [:settings, :billing], action: [:delete]}
    ]

    assert AccessPolicy.evaluate(:editor, :settings, :delete, policies) == :deny
    assert AccessPolicy.evaluate(:editor, :billing, :delete, policies) == :deny
    assert AccessPolicy.evaluate(:admin, :settings, :delete, policies) == :allow
    assert AccessPolicy.evaluate(:editor, :settings, :read, policies) == :allow
  end
end
