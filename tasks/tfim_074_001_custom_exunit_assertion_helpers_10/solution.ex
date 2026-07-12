    test "fails when the field exists but the message doesn't match" do
      cs = make_changeset(name: {"can't be blank", []})

      result =
        try do
          assert_changeset_error(cs, :name, "is too short")
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "name"
      assert result =~ "can't be blank"
    end