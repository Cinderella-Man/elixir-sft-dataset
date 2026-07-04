  test "removing an element that was never added raises ArgumentError", %{s: s} do
    assert_raise ArgumentError, fn ->
      TwoPhaseSet.remove(s, :never_added)
    end
  end