    test "passes for DateTime.utc_now()" do
      # apply/3 returns dynamic(term()), preventing the type checker from
      # narrowing to %DateTime{} and flagging the %NaiveDateTime{} branch in
      # the macro's case expression as unreachable.
      assert_recent(apply(DateTime, :utc_now, []))
    end