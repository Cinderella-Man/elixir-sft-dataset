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