    test "passes for a NaiveDateTime within tolerance" do
      # Same rationale: apply/3 keeps the type opaque so both branches remain
      # reachable in the type checker's view.
      just_now = apply(NaiveDateTime, :utc_now, [])
      assert_recent(just_now, 5)
    end