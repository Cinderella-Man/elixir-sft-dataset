    test "a message that is only a substring of the actual error does not match" do
      cs = make_changeset(name: {"can't be blank", []})

      assert_raise ExUnit.AssertionError, fn ->
        assert_changeset_error(cs, :name, "blank")
      end
    end