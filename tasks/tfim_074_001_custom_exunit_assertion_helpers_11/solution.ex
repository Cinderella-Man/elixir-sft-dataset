    test "fails when the field has no errors at all" do
      cs = make_changeset(email: {"is invalid", []})

      result =
        try do
          assert_changeset_error(cs, :name, "can't be blank")
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "name"
    end