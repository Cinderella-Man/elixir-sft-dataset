# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule PromoCodesTest do
  use ExUnit.Case, async: false

  # --- Deterministic clock returning a DateTime ---

  defmodule Clock do
    use Agent

    @base ~U[2026-06-01 00:00:00Z]

    def start_link(_ \\ nil) do
      Agent.start_link(fn -> @base end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def set(%DateTime{} = dt), do: Agent.update(__MODULE__, fn _ -> dt end)
    def base, do: @base
  end

  @past ~U[2020-01-01 00:00:00Z]
  @future ~U[2030-01-01 00:00:00Z]

  setup do
    start_supervised!(Clock)
    start_supervised!({PromoCodes, clock: &Clock.now/0})
    :ok
  end

  # -------------------------------------------------------
  # create/1
  # -------------------------------------------------------

  test "create returns {:ok, code} for a valid percentage code" do
    assert {:ok, _code} =
             PromoCodes.create(%{code: "SAVE20", type: :percentage, value: 20})
  end

  test "create rejects duplicate codes" do
    assert {:ok, _} = PromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             PromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})
  end

  test "create rejects an invalid discount type" do
    assert {:error, :invalid_type} =
             PromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end

  # -------------------------------------------------------
  # Discount type calculations
  # -------------------------------------------------------

  test "percentage: 50% off a $100 order returns $50" do
    {:ok, _} = PromoCodes.create(%{code: "HALF", type: :percentage, value: 50})
    assert {:ok, 5_000} = PromoCodes.apply("HALF", 10_000)
  end

  test "percentage: 20% off a $100 order returns $20" do
    {:ok, _} = PromoCodes.create(%{code: "TWENTY", type: :percentage, value: 20})
    assert {:ok, 2_000} = PromoCodes.apply("TWENTY", 10_000)
  end

  test "percentage discount is an integer (rounded)" do
    {:ok, _} = PromoCodes.create(%{code: "THIRD", type: :percentage, value: 33})
    assert {:ok, discount} = PromoCodes.apply("THIRD", 10_000)
    assert discount == 3_300
    assert is_integer(discount)
  end

  test "percentage discount rounds a fractional result to the nearest cent" do
    {:ok, _} = PromoCodes.create(%{code: "R33", type: :percentage, value: 33})

    # 999 * 33 / 100 == 329.67 -> rounds up to 330 (truncation would give 329)
    assert {:ok, 330} = PromoCodes.apply("R33", 999)

    # 1001 * 33 / 100 == 330.33 -> rounds down to 330 (ceiling would give 331)
    assert {:ok, 330} = PromoCodes.apply("R33", 1_001)
  end

  test "percentage discount rounds an exact half-cent up to the next cent" do
    {:ok, _} = PromoCodes.create(%{code: "R50", type: :percentage, value: 50})

    # 1001 * 50 / 100 == 500.5 -> round/1 goes up to 501
    # (truncation gives 500, and round-half-to-even would also give 500)
    assert {:ok, 501} = PromoCodes.apply("R50", 1_001)

    # 4999 * 50 / 100 == 2499.5 -> 2500 under the same rule
    assert {:ok, 2_500} = PromoCodes.apply("R50", 4_999)
  end

  test "fixed_amount: $15 off returns 1500" do
    {:ok, _} = PromoCodes.create(%{code: "FIX15", type: :fixed_amount, value: 1_500})
    assert {:ok, 1_500} = PromoCodes.apply("FIX15", 10_000)
  end

  test "fixed_amount never exceeds the order total" do
    {:ok, _} = PromoCodes.create(%{code: "BIG", type: :fixed_amount, value: 5_000})
    assert {:ok, 3_000} = PromoCodes.apply("BIG", 3_000)
  end

  test "free_shipping returns the configured waived shipping amount" do
    {:ok, _} = PromoCodes.create(%{code: "SHIP", type: :free_shipping, value: 999})
    assert {:ok, 999} = PromoCodes.apply("SHIP", 10_000)
  end

  # -------------------------------------------------------
  # not_found
  # -------------------------------------------------------

  test "applying an unknown code returns :not_found" do
    assert {:error, :not_found} = PromoCodes.apply("NOPE", 10_000)
  end

  # -------------------------------------------------------
  # Time window constraints
  # -------------------------------------------------------

  test "not-yet-valid code returns :not_yet_valid" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "SOON",
        type: :percentage,
        value: 10,
        valid_from: @future
      })

    assert {:error, :not_yet_valid} = PromoCodes.apply("SOON", 10_000)
  end

  test "expired code returns :expired" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "OLD",
        type: :percentage,
        value: 10,
        valid_until: @past
      })

    assert {:error, :expired} = PromoCodes.apply("OLD", 10_000)
  end

  test "code inside its validity window applies successfully" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "NOW",
        type: :percentage,
        value: 10,
        valid_from: @past,
        valid_until: @future
      })

    assert {:ok, 1_000} = PromoCodes.apply("NOW", 10_000)
  end

  test "validity boundaries are inclusive" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    # now == valid_from == valid_until
    assert {:ok, 1_000} = PromoCodes.apply("EDGE", 10_000)
  end

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

  # -------------------------------------------------------
  # Minimum order total
  # -------------------------------------------------------

  test "order below minimum returns :below_min_order" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "MIN50",
        type: :percentage,
        value: 10,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("MIN50", 3_000)
  end

  test "order exactly at the minimum passes" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "MIN50EQ",
        type: :percentage,
        value: 10,
        min_order_total: 5_000
      })

    assert {:ok, 500} = PromoCodes.apply("MIN50EQ", 5_000)
  end

  test "percentage discount combined with a minimum order total" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "COMBO",
        type: :percentage,
        value: 50,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("COMBO", 3_000)
    assert {:ok, 5_000} = PromoCodes.apply("COMBO", 10_000)
    assert {:ok, 2_500} = PromoCodes.apply("COMBO", 5_000)
  end

  test "free_shipping still respects the minimum order total" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "FREESHIPMIN",
        type: :free_shipping,
        value: 999,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = PromoCodes.apply("FREESHIPMIN", 3_000)
    assert {:ok, 999} = PromoCodes.apply("FREESHIPMIN", 5_000)
  end

  # -------------------------------------------------------
  # max_uses (total)
  # -------------------------------------------------------

  test "total max_uses is enforced" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "TWICE",
        type: :fixed_amount,
        value: 500,
        max_uses: 2
      })

    assert {:ok, 500} = PromoCodes.apply("TWICE", 10_000)
    assert {:ok, 500} = PromoCodes.apply("TWICE", 10_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("TWICE", 10_000)
  end

  test "failed applications do not consume uses" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "NOCONSUME",
        type: :fixed_amount,
        value: 500,
        max_uses: 1,
        min_order_total: 5_000
      })

    # Below minimum -> error, must NOT consume the single available use
    assert {:error, :below_min_order} = PromoCodes.apply("NOCONSUME", 1_000)

    # The one real use is still available
    assert {:ok, 500} = PromoCodes.apply("NOCONSUME", 5_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("NOCONSUME", 5_000)
  end

  # -------------------------------------------------------
  # max_uses_per_user
  # -------------------------------------------------------

  test "per-user max_uses is enforced independently per user" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "ONEEACH",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    assert {:ok, 500} = PromoCodes.apply("ONEEACH", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             PromoCodes.apply("ONEEACH", 10_000, user_id: "u1")

    # Different user is unaffected
    assert {:ok, 500} = PromoCodes.apply("ONEEACH", 10_000, user_id: "u2")
  end

  # -------------------------------------------------------
  # Multiple codes independence
  # -------------------------------------------------------

  test "different codes are tracked independently" do
    {:ok, _} = PromoCodes.create(%{code: "A", type: :percentage, value: 10, max_uses: 1})
    {:ok, _} = PromoCodes.create(%{code: "B", type: :fixed_amount, value: 250})

    assert {:ok, 1_000} = PromoCodes.apply("A", 10_000)
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("A", 10_000)

    # B is completely unaffected by A being exhausted
    assert {:ok, 250} = PromoCodes.apply("B", 10_000)
    assert {:ok, 250} = PromoCodes.apply("B", 10_000)
  end

  test "an anonymous application does not consume any user's per-user quota" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "ANONPU",
        type: :fixed_amount,
        value: 500,
        max_uses_per_user: 1
      })

    # No :user_id -> counts toward the (unlimited) total, tracked for nobody.
    assert {:ok, 500} = PromoCodes.apply("ANONPU", 10_000)
    assert {:ok, 500} = PromoCodes.apply("ANONPU", 10_000)

    # u1 still has their full per-user allowance.
    assert {:ok, 500} = PromoCodes.apply("ANONPU", 10_000, user_id: "u1")

    assert {:error, :max_uses_per_user_exceeded} =
             PromoCodes.apply("ANONPU", 10_000, user_id: "u1")
  end

  test "a successful application by a user also consumes the shared total max_uses" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "SHAREDTOTAL",
        type: :fixed_amount,
        value: 500,
        max_uses: 2
      })

    assert {:ok, 500} = PromoCodes.apply("SHAREDTOTAL", 10_000, user_id: "u1")
    assert {:ok, 500} = PromoCodes.apply("SHAREDTOTAL", 10_000, user_id: "u2")

    # Total is exhausted for everyone, including anonymous callers and new users.
    assert {:error, :max_uses_exceeded} = PromoCodes.apply("SHAREDTOTAL", 10_000)

    assert {:error, :max_uses_exceeded} =
             PromoCodes.apply("SHAREDTOTAL", 10_000, user_id: "u3")
  end

  test "total max_uses failure takes precedence over the per-user limit failure" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "PRECUSES",
        type: :fixed_amount,
        value: 500,
        max_uses: 1,
        max_uses_per_user: 1
      })

    assert {:ok, 500} = PromoCodes.apply("PRECUSES", 10_000, user_id: "u1")

    # Both limits are now blown for u1; the total limit is checked first.
    assert {:error, :max_uses_exceeded} =
             PromoCodes.apply("PRECUSES", 10_000, user_id: "u1")
  end

  test "expiry is reported before the minimum order total check" do
    {:ok, _} =
      PromoCodes.create(%{
        code: "PRECEXP",
        type: :percentage,
        value: 10,
        min_order_total: 5_000,
        valid_until: @past
      })

    # Order is also below the minimum, but expiry is evaluated first.
    assert {:error, :expired} = PromoCodes.apply("PRECEXP", 1_000)
  end

  test "min_order_total defaults to zero so any order total passes the check" do
    {:ok, _} = PromoCodes.create(%{code: "NOMIN", type: :percentage, value: 10})

    assert {:ok, 0} = PromoCodes.apply("NOMIN", 0)
    assert {:ok, 1} = PromoCodes.apply("NOMIN", 5)
    assert {:ok, 1_000} = PromoCodes.apply("NOMIN", 10_000)
  end

  test "start_link registers the process under an explicit :name option" do
    pid = start_supervised!({PromoCodes, [clock: &Clock.now/0, name: :promo_alt]}, id: :promo_alt)

    assert is_pid(pid)
    assert Process.whereis(:promo_alt) == pid

    # The default singleton is untouched and still serves the public API.
    assert Process.whereis(PromoCodes) != pid
    assert {:ok, _} = PromoCodes.create(%{code: "NAMED", type: :percentage, value: 10})
    assert {:ok, 1_000} = PromoCodes.apply("NAMED", 10_000)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
