    test "missing effect defaults to allow" do
      policies = [%{roles: [:viewer], resource: :docs, action: :read}]
      assert AccessPolicy.authorized?(:viewer, :docs, :read, policies)
    end