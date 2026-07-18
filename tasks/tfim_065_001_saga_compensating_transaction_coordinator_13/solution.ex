  test "a compensation returning an arbitrary term is recorded verbatim" do
    saga =
      Saga.new()
      |> Saga.step(:a, ok_action(:a, 1), comp(:a, :just_a_bare_atom))
      |> Saga.step(:b, ok_action(:b, 2), comp(:b, %{weird: [1, 2, 3]}))
      |> Saga.step(:c, fail_action(:c, :stop), comp(:c))

    assert {:error, err} = Saga.execute(saga, %{})

    assert err.compensated == [:b, :a]
    assert err.compensations == %{a: :just_a_bare_atom, b: %{weird: [1, 2, 3]}}
  end