    test "no matching pattern returns false" do
      refute Rbac.permitted?([:viewer], :settings, :update, @roles)
    end