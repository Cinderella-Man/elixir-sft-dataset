  test "start_link registers the process under an explicit :name option" do
    pid = start_supervised!({PromoCodes, [clock: &Clock.now/0, name: :promo_alt]}, id: :promo_alt)

    assert is_pid(pid)
    assert Process.whereis(:promo_alt) == pid

    # The default singleton is untouched and still serves the public API.
    assert Process.whereis(PromoCodes) != pid
    assert {:ok, _} = PromoCodes.create(%{code: "NAMED", type: :percentage, value: 10})
    assert {:ok, 1_000} = PromoCodes.apply("NAMED", 10_000)
  end