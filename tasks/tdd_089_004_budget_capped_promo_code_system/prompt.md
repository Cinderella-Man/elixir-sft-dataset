# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule BudgetPromoCodesTest do
  use ExUnit.Case, async: false

  defmodule Clock do
    use Agent
    @base ~U[2026-06-01 00:00:00Z]
    def start_link(_ \\ nil), do: Agent.start_link(fn -> @base end, name: __MODULE__)
    def now, do: Agent.get(__MODULE__, & &1)
    def set(%DateTime{} = dt), do: Agent.update(__MODULE__, fn _ -> dt end)
    def base, do: @base
  end

  @past ~U[2020-01-01 00:00:00Z]
  @future ~U[2030-01-01 00:00:00Z]

  setup do
    start_supervised!(Clock)
    start_supervised!({BudgetPromoCodes, clock: &Clock.now/0})
    :ok
  end

  # --- create ---

  test "create accepts a valid code" do
    assert {:ok, _} =
             BudgetPromoCodes.create(%{code: "B", type: :fixed_amount, value: 500, budget: 1_000})
  end

  test "create rejects duplicates and invalid type" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             BudgetPromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})

    assert {:error, :invalid_type} =
             BudgetPromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end

  # --- basic discounts (no budget) ---

  test "unbudgeted percentage discount" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "HALF", type: :percentage, value: 50})
    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("HALF", 10_000)
    assert {:ok, :unlimited} = BudgetPromoCodes.remaining_budget("HALF")
  end

  test "unbudgeted code dispenses the full discount every time" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "F5", type: :fixed_amount, value: 500})
    assert {:ok, 500} = BudgetPromoCodes.apply_code("F5", 10_000)
    assert {:ok, 500} = BudgetPromoCodes.apply_code("F5", 10_000)
    assert {:ok, 1_000} = BudgetPromoCodes.dispensed("F5")
  end

  # --- budget clipping (fixed) ---

  test "fixed-amount budget clips the final application and then exhausts" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "FB", type: :fixed_amount, value: 5_000, budget: 8_000})

    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 3_000} = BudgetPromoCodes.remaining_budget("FB")
    # clipped to remaining 3_000
    assert {:ok, 3_000} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 0} = BudgetPromoCodes.remaining_budget("FB")
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 8_000} = BudgetPromoCodes.dispensed("FB")
  end

  # --- budget clipping (percentage) ---

  test "percentage budget clips a large discount" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "PB", type: :percentage, value: 50, budget: 6_000})

    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("PB", 10_000)
    assert {:ok, 1_000} = BudgetPromoCodes.apply_code("PB", 10_000)
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("PB", 10_000)
  end

  # --- free shipping honors budget ---

  test "free shipping draws from budget" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "SB", type: :free_shipping, value: 999, budget: 1_500})

    assert {:ok, 999} = BudgetPromoCodes.apply_code("SB", 10_000)
    assert {:ok, 501} = BudgetPromoCodes.apply_code("SB", 10_000)
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("SB", 10_000)
  end

  # --- precedence & failed applications ---

  test "unknown code returns :not_found" do
    assert {:error, :not_found} = BudgetPromoCodes.apply_code("NOPE", 10_000)
    assert {:error, :not_found} = BudgetPromoCodes.remaining_budget("NOPE")
    assert {:error, :not_found} = BudgetPromoCodes.dispensed("NOPE")
  end

  test "below minimum order does not touch budget" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "MIN",
        type: :fixed_amount,
        value: 500,
        budget: 1_000,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("MIN", 3_000)
    assert {:ok, 1_000} = BudgetPromoCodes.remaining_budget("MIN")
    assert {:ok, 0} = BudgetPromoCodes.dispensed("MIN")
  end

  test "max_uses is enforced ahead of budget exhaustion" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "MU",
        type: :fixed_amount,
        value: 100,
        budget: 10_000,
        max_uses: 2
      })

    assert {:ok, 100} = BudgetPromoCodes.apply_code("MU", 10_000)
    assert {:ok, 100} = BudgetPromoCodes.apply_code("MU", 10_000)
    assert {:error, :max_uses_exceeded} = BudgetPromoCodes.apply_code("MU", 10_000)
  end

  test "time window is enforced with inclusive boundaries" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "SOON", type: :percentage, value: 10, valid_from: @future})

    assert {:error, :not_yet_valid} = BudgetPromoCodes.apply_code("SOON", 10_000)

    {:ok, _} =
      BudgetPromoCodes.create(%{code: "OLD", type: :percentage, value: 10, valid_until: @past})

    assert {:error, :expired} = BudgetPromoCodes.apply_code("OLD", 10_000)

    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, 1_000} = BudgetPromoCodes.apply_code("EDGE", 10_000)
  end

  test "clock advancing past valid_until exhausts nothing but expires the code" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "WIN",
        type: :fixed_amount,
        value: 500,
        budget: 5_000,
        valid_until: ~U[2026-06-10 00:00:00Z]
      })

    assert {:ok, 500} = BudgetPromoCodes.apply_code("WIN", 10_000)
    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:error, :expired} = BudgetPromoCodes.apply_code("WIN", 10_000)
    assert {:ok, 4_500} = BudgetPromoCodes.remaining_budget("WIN")
  end

  test "order total exactly equal to min_order_total is accepted" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "EQ",
        type: :fixed_amount,
        value: 500,
        budget: 1_000,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("EQ", 4_999)
    assert {:ok, 500} = BudgetPromoCodes.apply_code("EQ", 5_000)
    assert {:ok, 500} = BudgetPromoCodes.remaining_budget("EQ")
    assert {:ok, 500} = BudgetPromoCodes.dispensed("EQ")
  end

  test "user_id does not grant a separate budget or extra uses" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "UID",
        type: :fixed_amount,
        value: 600,
        budget: 1_000,
        max_uses: 2
      })

    assert {:ok, 600} = BudgetPromoCodes.apply_code("UID", 10_000, user_id: "alice")
    # second user draws from the SAME shared budget, clipped to what is left
    assert {:ok, 400} = BudgetPromoCodes.apply_code("UID", 10_000, user_id: "bob")
    assert {:ok, 0} = BudgetPromoCodes.remaining_budget("UID")
    # total uses are counted across users, not per user
    assert {:error, :max_uses_exceeded} =
             BudgetPromoCodes.apply_code("UID", 10_000, user_id: "carol")

    assert {:ok, 1_000} = BudgetPromoCodes.dispensed("UID")
  end

  test "failed applications do not consume a use" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "FAIL",
        type: :fixed_amount,
        value: 100,
        budget: 1_000,
        max_uses: 1,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("FAIL", 100)
    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("FAIL", 4_999, user_id: "u1")
    # the single permitted use must still be available
    assert {:ok, 100} = BudgetPromoCodes.apply_code("FAIL", 5_000)
    assert {:error, :max_uses_exceeded} = BudgetPromoCodes.apply_code("FAIL", 5_000)
    assert {:ok, 100} = BudgetPromoCodes.dispensed("FAIL")
    assert {:ok, 900} = BudgetPromoCodes.remaining_budget("FAIL")
  end

  test "fixed amount discount is capped at the order total" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "CAP", type: :fixed_amount, value: 5_000})
    assert {:ok, 3_000} = BudgetPromoCodes.apply_code("CAP", 3_000)
    assert {:ok, 0} = BudgetPromoCodes.apply_code("CAP", 0)
    assert {:ok, 3_000} = BudgetPromoCodes.dispensed("CAP")
  end

  test "percentage discount rounds fractional cents" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "RND", type: :percentage, value: 10})
    # 105 * 10 / 100 = 10.5 -> 11
    assert {:ok, 11} = BudgetPromoCodes.apply_code("RND", 105)

    {:ok, _} = BudgetPromoCodes.create(%{code: "RND3", type: :percentage, value: 33})
    # 101 * 33 / 100 = 33.33 -> 33
    assert {:ok, 33} = BudgetPromoCodes.apply_code("RND3", 101)
    assert {:ok, 11} = BudgetPromoCodes.dispensed("RND")
  end

  test "earlier checks win over later failures for the same application" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "PREC",
        type: :fixed_amount,
        value: 100,
        budget: 0,
        max_uses: 0,
        min_order_total: 10_000,
        valid_until: @past
      })

    assert {:error, :expired} = BudgetPromoCodes.apply_code("PREC", 1)

    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "PREC2",
        type: :percentage,
        value: 10,
        budget: 0,
        max_uses: 0,
        min_order_total: 10_000,
        valid_from: @future,
        valid_until: @past
      })

    assert {:error, :not_yet_valid} = BudgetPromoCodes.apply_code("PREC2", 1)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
