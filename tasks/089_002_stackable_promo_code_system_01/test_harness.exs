defmodule StackablePromoCodesTest do
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
    start_supervised!({StackablePromoCodes, clock: &Clock.now/0})
    :ok
  end

  defp find(list, code), do: Enum.find(list, &(&1.code == code))

  # --- create ---

  test "create returns {:ok, code} for a valid code" do
    assert {:ok, _} = StackablePromoCodes.create(%{code: "P20", type: :percentage, value: 20})
  end

  test "create rejects duplicate codes" do
    assert {:ok, _} = StackablePromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             StackablePromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})
  end

  test "create rejects an invalid type" do
    assert {:error, :invalid_type} =
             StackablePromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end

  # --- empty list ---

  test "empty code list returns :no_codes" do
    assert {:error, :no_codes} = StackablePromoCodes.apply_codes([], 10_000)
  end

  # --- stacking of a percentage and a fixed code ---

  test "a percentage and a fixed code stack" do
    {:ok, _} = StackablePromoCodes.create(%{code: "PCT20", type: :percentage, value: 20})
    {:ok, _} = StackablePromoCodes.create(%{code: "FIX15", type: :fixed_amount, value: 1_500})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["PCT20", "FIX15"], 10_000)
    # 20% of 10_000 = 2_000; then 1_500 off the remaining 8_000
    assert r.total_discount == 3_500
    assert r.final_total == 6_500
    assert find(r.applied, "PCT20").discount == 2_000
    assert find(r.applied, "FIX15").discount == 1_500
    assert r.rejected == []
  end

  # --- only the best percentage applies ---

  test "only the highest percentage code applies; others rejected" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P20", type: :percentage, value: 20})
    {:ok, _} = StackablePromoCodes.create(%{code: "P50", type: :percentage, value: 50})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["P20", "P50"], 10_000)
    assert find(r.applied, "P50").discount == 5_000
    assert find(r.applied, "P20") == nil
    assert find(r.rejected, "P20").reason == :percentage_already_applied
    assert r.total_discount == 5_000
  end

  # --- free shipping stacks with a percentage ---

  test "free shipping stacks with a percentage" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P10", type: :percentage, value: 10})
    {:ok, _} = StackablePromoCodes.create(%{code: "SHIP", type: :free_shipping, value: 999})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["P10", "SHIP"], 10_000)
    assert find(r.applied, "P10").discount == 1_000
    assert find(r.applied, "SHIP").discount == 999
    assert r.total_discount == 1_999
    assert r.final_total == 8_001
  end

  test "only one free shipping code applies" do
    {:ok, _} = StackablePromoCodes.create(%{code: "S1", type: :free_shipping, value: 500})
    {:ok, _} = StackablePromoCodes.create(%{code: "S2", type: :free_shipping, value: 700})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["S1", "S2"], 10_000)
    assert find(r.applied, "S1").discount == 500
    assert find(r.rejected, "S2").reason == :free_shipping_already_applied
  end

  # --- total discount capped at the order total ---

  test "total discount never exceeds the order total" do
    {:ok, _} = StackablePromoCodes.create(%{code: "BIG", type: :fixed_amount, value: 5_000})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["BIG"], 3_000)
    assert find(r.applied, "BIG").discount == 3_000
    assert r.total_discount == 3_000
    assert r.final_total == 0
  end

  # --- invalid codes rejected, valid ones still apply ---

  test "unknown code is rejected while valid codes apply" do
    {:ok, _} = StackablePromoCodes.create(%{code: "GOOD", type: :fixed_amount, value: 250})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["GOOD", "NOPE"], 10_000)
    assert find(r.applied, "GOOD").discount == 250
    assert find(r.rejected, "NOPE").reason == :not_found
  end

  test "duplicate code in the same order is rejected once" do
    {:ok, _} = StackablePromoCodes.create(%{code: "F5", type: :fixed_amount, value: 500})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["F5", "F5"], 10_000)
    assert length(Enum.filter(r.applied, &(&1.code == "F5"))) == 1
    assert find(r.rejected, "F5").reason == :duplicate_in_order
  end

  test "below-minimum code is rejected but others apply" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "MIN",
        type: :fixed_amount,
        value: 500,
        min_order_total: 5_000
      })

    {:ok, _} = StackablePromoCodes.create(%{code: "ANY", type: :fixed_amount, value: 250})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["MIN", "ANY"], 3_000)
    assert find(r.rejected, "MIN").reason == :below_min_order
    assert find(r.applied, "ANY").discount == 250
  end

  # --- usage accounting ---

  test "only applied codes consume uses" do
    {:ok, _} =
      StackablePromoCodes.create(%{code: "ONCE", type: :fixed_amount, value: 500, max_uses: 1})

    {:ok, _} = StackablePromoCodes.create(%{code: "DUPE", type: :percentage, value: 10})
    {:ok, _} = StackablePromoCodes.create(%{code: "DUPE2", type: :percentage, value: 20})

    # DUPE loses to DUPE2 and is rejected -> must not consume
    assert {:ok, _} = StackablePromoCodes.apply_codes(["ONCE", "DUPE", "DUPE2"], 10_000)
    assert {:ok, r} = StackablePromoCodes.apply_codes(["ONCE"], 10_000)
    assert find(r.rejected, "ONCE").reason == :max_uses_exceeded

    # DUPE was never consumed, still usable
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["DUPE"], 10_000)
    assert find(r2.applied, "DUPE").discount == 1_000
  end

  test "per-user limit is enforced independently" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "PU",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    assert {:ok, r1} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u1")
    assert find(r1.applied, "PU")
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u1")
    assert find(r2.rejected, "PU").reason == :max_uses_per_user_exceeded
    assert {:ok, r3} = StackablePromoCodes.apply_codes(["PU"], 10_000, user_id: "u2")
    assert find(r3.applied, "PU").discount == 500
  end

  # --- time window ---

  test "expired code is rejected once the clock advances" do
    valid_until = ~U[2026-06-10 00:00:00Z]

    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "WIN",
        type: :percentage,
        value: 10,
        valid_until: valid_until
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["WIN"], 10_000)
    assert find(r.applied, "WIN").discount == 1_000

    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["WIN"], 10_000)
    assert find(r2.rejected, "WIN").reason == :expired
  end

  test "not-yet-valid and inclusive boundaries" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "SOON",
        type: :percentage,
        value: 10,
        valid_from: @future
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["SOON"], 10_000)
    assert find(r.rejected, "SOON").reason == :not_yet_valid

    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, r2} = StackablePromoCodes.apply_codes(["EDGE"], 10_000)
    assert find(r2.applied, "EDGE").discount == 1_000
    assert @past
  end

  test "each discount is capped at the remaining total in prompt order" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P90", type: :percentage, value: 90})
    {:ok, _} = StackablePromoCodes.create(%{code: "SH", type: :free_shipping, value: 500})
    {:ok, _} = StackablePromoCodes.create(%{code: "FA", type: :fixed_amount, value: 400})
    {:ok, _} = StackablePromoCodes.create(%{code: "FB", type: :fixed_amount, value: 300})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["FA", "SH", "FB", "P90"], 1_000)
    assert find(r.applied, "P90").discount == 900
    assert find(r.applied, "P90").type == :percentage
    assert find(r.applied, "SH").discount == 100
    assert find(r.applied, "FA").discount == 0
    assert find(r.applied, "FB").discount == 0
    assert r.total_discount == 1_000
    assert r.final_total == 0
    assert r.rejected == []
  end

  test "expiry outranks the minimum-order check for the same code" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "OLD",
        type: :fixed_amount,
        value: 500,
        min_order_total: 50_000,
        valid_until: ~U[2026-05-01 00:00:00Z]
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["OLD"], 1_000)
    assert find(r.rejected, "OLD").reason == :expired
    assert r.applied == []
    assert r.total_discount == 0
  end

  test "an order total exactly equal to min_order_total applies the code" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "MIN5K",
        type: :fixed_amount,
        value: 500,
        min_order_total: 5_000
      })

    {:ok, _} = StackablePromoCodes.create(%{code: "NOMIN", type: :fixed_amount, value: 100})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["MIN5K", "NOMIN"], 5_000)
    assert find(r.applied, "MIN5K").discount == 500
    assert find(r.applied, "NOMIN").discount == 100
    assert r.rejected == []
    assert r.final_total == 4_400
  end

  test "max_uses and max_uses_per_user default to unlimited applications" do
    {:ok, _} = StackablePromoCodes.create(%{code: "FREE", type: :fixed_amount, value: 100})

    for _ <- 1..3 do
      assert {:ok, r} = StackablePromoCodes.apply_codes(["FREE"], 10_000, user_id: "u1")
      assert find(r.applied, "FREE").discount == 100
      assert r.rejected == []
    end
  end

  test "max_uses counts applications across all users" do
    {:ok, _} =
      StackablePromoCodes.create(%{code: "CAP2", type: :fixed_amount, value: 500, max_uses: 2})

    assert {:ok, r1} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u1")
    assert find(r1.applied, "CAP2").discount == 500
    assert {:ok, r2} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u2")
    assert find(r2.applied, "CAP2").discount == 500
    assert {:ok, r3} = StackablePromoCodes.apply_codes(["CAP2"], 10_000, user_id: "u3")
    assert find(r3.rejected, "CAP2").reason == :max_uses_exceeded
    assert r3.applied == []
  end

  test "not-yet-valid outranks expired when both window checks fail" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "BOTH",
        type: :percentage,
        value: 10,
        valid_from: @future,
        valid_until: @past
      })

    assert {:ok, r} = StackablePromoCodes.apply_codes(["BOTH"], 10_000)
    assert find(r.rejected, "BOTH").reason == :not_yet_valid
  end
end
