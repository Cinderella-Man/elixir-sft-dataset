  test "list membership in resource field" do
    policies = [%{effect: :allow, roles: :any, resource: [:posts, :docs], action: :read}]

    assert AccessPolicy.authorized?(:viewer, :posts, :read, policies)
    assert AccessPolicy.authorized?(:viewer, :docs, :read, policies)
    refute AccessPolicy.authorized?(:viewer, :settings, :read, policies)
  end