    test "passes when the exact error is present on the field" do
      cs = make_changeset(name: {"can't be blank", []}, email: {"is invalid", []})
      assert_changeset_error(cs, :name, "can't be blank")
    end