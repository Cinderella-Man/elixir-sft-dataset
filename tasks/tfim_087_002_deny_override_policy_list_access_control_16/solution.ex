  test "list membership in action field" do
    policies = [%{effect: :allow, roles: :any, resource: :posts, action: [:read, :write]}]

    assert AccessPolicy.authorized?(:viewer, :posts, :read, policies)
    assert AccessPolicy.authorized?(:viewer, :posts, :write, policies)
    refute AccessPolicy.authorized?(:viewer, :posts, :delete, policies)
  end