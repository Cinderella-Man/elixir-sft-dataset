    test "an actual error that is only a substring of the expected does not match" do
      cs = make_changeset(email: {"is invalid", []})

      assert_raise ExUnit.AssertionError, fn ->
        assert_changeset_error(cs, :email, "is invalid, must be a work address")
      end
    end