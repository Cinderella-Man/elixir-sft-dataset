  test "authorized? returns exact booleans, never nil or other truthy values" do
    policies = [%{effect: :allow, roles: [:admin], resource: :any, action: :any}]

    assert AccessPolicy.authorized?(:admin, :posts, :read, policies) === true
    assert AccessPolicy.authorized?(:viewer, :posts, :read, policies) === false
    assert AccessPolicy.authorized?(:admin, :posts, :read, []) === false
  end