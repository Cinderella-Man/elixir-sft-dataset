  test "effective_permissions of roles plus grants is exactly the merged set" do
    principal = %{roles: [:moderator], grants: ["comments:*", "billing:refund"]}

    assert Rbac.effective_permissions(principal, @roles) ==
             MapSet.new(["comments:*", "billing:refund"])
  end