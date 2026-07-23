    test "a message present on another field does not satisfy the assertion" do
      cs = make_changeset(email: {"is invalid", []})

      assert_raise ExUnit.AssertionError, fn ->
        assert_changeset_error(cs, :name, "is invalid")
      end
    end