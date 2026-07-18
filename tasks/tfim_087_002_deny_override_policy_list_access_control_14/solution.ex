  test "scalar role atom in :roles matches only that exact role" do
    policies = [%{effect: :allow, roles: :viewer, resource: :docs, action: :read}]

    assert AccessPolicy.evaluate(:viewer, :docs, :read, policies) == :allow
    assert AccessPolicy.evaluate(:editor, :docs, :read, policies) == :deny
  end