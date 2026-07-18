  test "a manual {:check, name} performs one check and the single chain keeps ticking", %{
    mon: mon
  } do
    check = reporting_check("folded", :ok)
    assert :ok = Monitor.register(mon, "folded", check, 400)

    trigger_check(mon, "folded")
    assert_receive {:checked, "folded"}, 500

    # The manual check folded into the chain (one live timer, cadence reset):
    # the next check arrives timer-driven, with no help from the test.
    assert_receive {:checked, "folded"}, 2_000
  end