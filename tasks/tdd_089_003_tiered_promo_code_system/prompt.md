# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule TieredPromoCodesTest do
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

  @pct_tiers [
    %{threshold: 0, type: :percentage, value: 5},
    %{threshold: 5_000, type: :percentage, value: 10},
    %{threshold: 10_000, type: :percentage, value: 20}
  ]

  setup do
    start_supervised!(Clock)
    start_supervised!({TieredPromoCodes, clock: &Clock.now/0})
    :ok
  end

  # --- create validation ---

  test "create accepts a valid tiered code" do
    assert {:ok, _} = TieredPromoCodes.create(%{code: "SPEND", tiers: @pct_tiers})
  end

  test "create rejects duplicates" do
    assert {:ok, _} = TieredPromoCodes.create(%{code: "DUP", tiers: @pct_tiers})
    assert {:error, :already_exists} = TieredPromoCodes.create(%{code: "DUP", tiers: @pct_tiers})
  end

  test "create rejects an empty tier list" do
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "E", tiers: []})
  end

  test "create rejects non-ascending thresholds" do
    tiers = [
      %{threshold: 5_000, type: :percentage, value: 10},
      %{threshold: 5_000, type: :percentage, value: 20}
    ]

    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NA", tiers: tiers})
  end

  test "create rejects an out-of-range percentage" do
    tiers = [%{threshold: 0, type: :percentage, value: 150}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BADP", tiers: tiers})
  end

  test "create rejects an unknown tier type" do
    tiers = [%{threshold: 0, type: :bogus, value: 10}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BADT", tiers: tiers})
  end

  # --- tier selection ---

  test "selects the correct tier by order total" do
    {:ok, _} = TieredPromoCodes.create(%{code: "SPEND", tiers: @pct_tiers})
    assert {:ok, 150} = TieredPromoCodes.apply_code("SPEND", 3_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("SPEND", 5_000)
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("SPEND", 10_000)
    assert {:ok, 2_400} = TieredPromoCodes.apply_code("SPEND", 12_000)
  end

  test "order below the smallest threshold returns :below_min_order" do
    tiers = [
      %{threshold: 5_000, type: :percentage, value: 10},
      %{threshold: 10_000, type: :percentage, value: 20}
    ]

    {:ok, _} = TieredPromoCodes.create(%{code: "HIGH", tiers: tiers})
    assert {:error, :below_min_order} = TieredPromoCodes.apply_code("HIGH", 3_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("HIGH", 5_000)
  end

  test "fixed-amount tiers cap at the order total" do
    tiers = [%{threshold: 0, type: :fixed_amount, value: 1_500}]
    {:ok, _} = TieredPromoCodes.create(%{code: "F15", tiers: tiers})
    assert {:ok, 1_000} = TieredPromoCodes.apply_code("F15", 1_000)
    assert {:ok, 1_500} = TieredPromoCodes.apply_code("F15", 10_000)
  end

  # --- preview ---

  test "preview returns discount and tier index without consuming a use" do
    {:ok, _} = TieredPromoCodes.create(%{code: "PV", tiers: @pct_tiers, max_uses: 1})
    assert {:ok, 500, 1} = TieredPromoCodes.preview("PV", 5_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PV", 10_000)
    # the single use is still available
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("PV", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("PV", 10_000)
  end

  test "preview reports :not_found and :below_min_order" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]
    {:ok, _} = TieredPromoCodes.create(%{code: "PVE", tiers: tiers})
    assert {:error, :not_found} = TieredPromoCodes.preview("NOPE", 5_000)
    assert {:error, :below_min_order} = TieredPromoCodes.preview("PVE", 1_000)
  end

  # --- errors and constraints ---

  test "unknown code returns :not_found" do
    assert {:error, :not_found} = TieredPromoCodes.apply_code("NOPE", 10_000)
  end

  test "max_uses is enforced" do
    {:ok, _} = TieredPromoCodes.create(%{code: "TWICE", tiers: @pct_tiers, max_uses: 2})
    assert {:ok, _} = TieredPromoCodes.apply_code("TWICE", 10_000)
    assert {:ok, _} = TieredPromoCodes.apply_code("TWICE", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("TWICE", 10_000)
  end

  test "failed application (below min) does not consume a use" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]
    {:ok, _} = TieredPromoCodes.create(%{code: "NC", tiers: tiers, max_uses: 1})
    assert {:error, :below_min_order} = TieredPromoCodes.apply_code("NC", 1_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("NC", 5_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("NC", 5_000)
  end

  test "per-user limit is enforced independently" do
    {:ok, _} = TieredPromoCodes.create(%{code: "PU", tiers: @pct_tiers, max_uses_per_user: 1})
    assert {:ok, _} = TieredPromoCodes.apply_code("PU", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             TieredPromoCodes.apply_code("PU", 10_000, user_id: "u1")

    assert {:ok, _} = TieredPromoCodes.apply_code("PU", 10_000, user_id: "u2")
  end

  test "time window is enforced with inclusive boundaries" do
    {:ok, _} = TieredPromoCodes.create(%{code: "SOON", tiers: @pct_tiers, valid_from: @future})
    assert {:error, :not_yet_valid} = TieredPromoCodes.apply_code("SOON", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "OLD", tiers: @pct_tiers, valid_until: @past})
    assert {:error, :expired} = TieredPromoCodes.apply_code("OLD", 10_000)

    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "EDGE",
        tiers: @pct_tiers,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("EDGE", 10_000)
  end

  test "create rejects a non-binary code with :invalid_code" do
    assert {:error, :invalid_code} = TieredPromoCodes.create(%{code: :atom, tiers: @pct_tiers})
    assert {:error, :invalid_code} = TieredPromoCodes.create(%{tiers: @pct_tiers})
  end

  test "preview ignores the time window and exhausted usage limits" do
    {:ok, _} =
      TieredPromoCodes.create(%{code: "PVW", tiers: @pct_tiers, valid_until: @past, max_uses: 1})

    assert {:error, :expired} = TieredPromoCodes.apply_code("PVW", 10_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PVW", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "PVU", tiers: @pct_tiers, max_uses: 1})
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("PVU", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("PVU", 10_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PVU", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "PVF", tiers: @pct_tiers, valid_from: @future})
    assert {:ok, 500, 1} = TieredPromoCodes.preview("PVF", 5_000)
  end

  test "expired window outranks a below-minimum order total" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]

    {:ok, _} =
      TieredPromoCodes.create(%{code: "EXPLOW", tiers: tiers, valid_until: @past})

    assert {:error, :expired} = TieredPromoCodes.apply_code("EXPLOW", 1_000)

    {:ok, _} =
      TieredPromoCodes.create(%{code: "SOONLOW", tiers: tiers, valid_from: @future})

    assert {:error, :not_yet_valid} = TieredPromoCodes.apply_code("SOONLOW", 1_000)
  end

  test "max_uses failure outranks the per-user failure when both are exhausted" do
    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "BOTH",
        tiers: @pct_tiers,
        max_uses: 1,
        max_uses_per_user: 1
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("BOTH", 10_000, user_id: "u1")

    assert {:error, :max_uses_exceeded} =
             TieredPromoCodes.apply_code("BOTH", 10_000, user_id: "u1")
  end

  test "create rejects malformed thresholds and negative values" do
    neg_threshold = [%{threshold: -1, type: :percentage, value: 10}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NT", tiers: neg_threshold})

    float_threshold = [%{threshold: 1_000.0, type: :percentage, value: 10}]

    assert {:error, :invalid_tiers} =
             TieredPromoCodes.create(%{code: "FT", tiers: float_threshold})

    neg_fixed = [%{threshold: 0, type: :fixed_amount, value: -5}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NF", tiers: neg_fixed})

    bad_value = [%{threshold: 0, type: :percentage, value: "10"}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BV", tiers: bad_value})

    not_a_map = [%{threshold: 0, type: :percentage, value: 10}, :nope]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NM", tiers: not_a_map})
  end

  test "a per-user rejection does not consume a total use" do
    {:ok, _} =
      TieredPromoCodes.create(%{
        code: "NOBURN",
        tiers: @pct_tiers,
        max_uses: 2,
        max_uses_per_user: 1
      })

    assert {:ok, 2_000} = TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u1")

    # the rejected attempt must not have burned the second total use
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u2")

    assert {:error, :max_uses_exceeded} =
             TieredPromoCodes.apply_code("NOBURN", 10_000, user_id: "u3")
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
