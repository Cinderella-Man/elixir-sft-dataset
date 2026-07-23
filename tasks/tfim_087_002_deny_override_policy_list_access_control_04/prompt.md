# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule AccessPolicy do
  @moduledoc """
  Policy-statement authorization with explicit-deny precedence.

  Authorization is decided by matching a request `{role, resource, action}`
  against a flat, order-independent list of statement maps. There is no role
  hierarchy: a request is `:allow`ed only when a matching allow statement
  exists and no matching deny statement exists.

  ## Statement shape

      %{
        effect:   :allow | :deny,          # default :allow
        roles:    atom | [atom] | :any,    # default :any
        resource: atom | [atom] | :any,    # default :any
        action:   atom | [atom] | :any     # default :any
      }

  ## Decision procedure

    1. If any matching statement has effect `:deny` -> `:deny`.
    2. Else if any matching statement has effect `:allow` -> `:allow`.
    3. Else (no match) -> `:deny` (default deny).

  Explicit deny always wins over allow, independent of list order.
  """

  @type effect :: :allow | :deny
  @type statement :: map()

  @doc """
  Evaluates a request against `policies`, returning `:allow` or `:deny`.
  """
  @spec evaluate(atom(), atom(), atom(), [statement()]) :: effect()
  def evaluate(role, resource, action, policies) when is_list(policies) do
    matching = Enum.filter(policies, &matches?(&1, role, resource, action))

    cond do
      Enum.any?(matching, &(effect_of(&1) == :deny)) -> :deny
      Enum.any?(matching, &(effect_of(&1) == :allow)) -> :allow
      true -> :deny
    end
  end

  @doc """
  Returns `true` when `evaluate/4` yields `:allow`, `false` otherwise.
  """
  @spec authorized?(atom(), atom(), atom(), [statement()]) :: boolean()
  def authorized?(role, resource, action, policies) do
    evaluate(role, resource, action, policies) == :allow
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp matches?(stmt, role, resource, action) do
    field_match?(Map.get(stmt, :roles, :any), role) and
      field_match?(Map.get(stmt, :resource, :any), resource) and
      field_match?(Map.get(stmt, :action, :any), action)
  end

  defp effect_of(stmt), do: Map.get(stmt, :effect, :allow)

  defp field_match?(:any, _value), do: true
  defp field_match?(expected, value) when is_list(expected), do: value in expected
  defp field_match?(expected, value), do: expected == value
end
```

## Test harness — implement the `# TODO` test

```elixir
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
      # TODO
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
```
