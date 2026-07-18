  test "code becomes expired once the clock advances past valid_until" do
    valid_until = ~U[2026-06-10 00:00:00Z]

    {:ok, _} =
      PromoCodes.create(%{
        code: "WINDOW",
        type: :percentage,
        value: 10,
        valid_until: valid_until
      })

    assert {:ok, 1_000} = PromoCodes.apply("WINDOW", 10_000)

    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:error, :expired} = PromoCodes.apply("WINDOW", 10_000)
  end