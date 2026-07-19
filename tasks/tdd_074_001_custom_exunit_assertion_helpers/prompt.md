# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
defmodule AssertHelpersTest do
  use ExUnit.Case, async: false
  use AssertHelpers

  # ── Fake Ecto-style changeset ──────────────────────────────────────────────

  defp make_changeset(errors) do
    # Mimics the shape ExUnit assertion helpers care about:
    # changeset.errors :: [{field, {message, opts}}]
    %{errors: errors}
  end

  # ── assert_changeset_error ─────────────────────────────────────────────────

  describe "assert_changeset_error/3" do
    test "passes when the exact error is present on the field" do
      cs = make_changeset(name: {"can't be blank", []}, email: {"is invalid", []})
      assert_changeset_error(cs, :name, "can't be blank")
    end

    test "passes when the field has multiple errors and one matches" do
      cs = make_changeset(age: {"must be greater than 0", []}, age: {"is invalid", []})
      assert_changeset_error(cs, :age, "is invalid")
    end

    test "fails when the field exists but the message doesn't match" do
      cs = make_changeset(name: {"can't be blank", []})

      result =
        try do
          assert_changeset_error(cs, :name, "is too short")
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "name"
      assert result =~ "can't be blank"
    end

    test "fails when the field has no errors at all" do
      cs = make_changeset(email: {"is invalid", []})

      result =
        try do
          assert_changeset_error(cs, :name, "can't be blank")
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "name"
    end

    test "fails when the changeset has no errors" do
      cs = make_changeset([])

      result =
        try do
          assert_changeset_error(cs, :name, "can't be blank")
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
    end
  end

  # ── assert_recent ──────────────────────────────────────────────────────────

  describe "assert_recent/2" do
    test "passes for DateTime.utc_now()" do
      # apply/3 returns dynamic(term()), preventing the type checker from
      # narrowing to %DateTime{} and flagging the %NaiveDateTime{} branch in
      # the macro's case expression as unreachable.
      assert_recent(apply(DateTime, :utc_now, []))
    end

    test "passes for a NaiveDateTime within tolerance" do
      # Same rationale: apply/3 keeps the type opaque so both branches remain
      # reachable in the type checker's view.
      just_now = apply(NaiveDateTime, :utc_now, [])
      assert_recent(just_now, 5)
    end

    test "passes for a datetime exactly at the tolerance boundary" do
      four_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -4, :second])
      assert_recent(four_seconds_ago, 5)
    end

    test "fails for a datetime well in the past" do
      old = apply(DateTime, :add, [DateTime.utc_now(), -60, :second])

      result =
        try do
          assert_recent(old, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "60" or result =~ "second"
    end

    test "fails for a datetime in the future beyond tolerance" do
      future = apply(DateTime, :add, [DateTime.utc_now(), 30, :second])

      result =
        try do
          assert_recent(future, 5)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
    end

    test "failure message includes the actual datetime and the diff" do
      old = apply(DateTime, :add, [DateTime.utc_now(), -100, :second])

      message =
        try do
          assert_recent(old, 5)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      # Should tell us both what the value was and how far off it is
      assert message =~ "tolerance"
    end
  end

  # ── assert_eventually ─────────────────────────────────────────────────────

  describe "assert_eventually/3" do
    test "passes immediately when the function is already truthy" do
      assert_eventually(fn -> true end)
    end

    test "passes when the function becomes truthy before timeout" do
      counter = :counters.new(1, [])

      assert_eventually(
        fn ->
          :counters.add(counter, 1, 1)
          :counters.get(counter, 1) >= 3
        end,
        500,
        20
      )
    end

    test "returns the truthy value from the function" do
      # assert_eventually should not raise; result is checked implicitly
      assert_eventually(fn -> 42 end)
    end

    test "fails when function never returns truthy within timeout" do
      result =
        try do
          assert_eventually(fn -> false end, 100, 20)
          :no_failure
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      refute result == :no_failure
      assert result =~ "timed out" or result =~ "timeout" or result =~ "100"
    end

    test "failure message includes last returned value" do
      message =
        try do
          assert_eventually(fn -> :still_pending end, 100, 40)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "still_pending"
    end

    test "failure message includes total time waited" do
      message =
        try do
          assert_eventually(fn -> nil end, 150, 40)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ "150" or message =~ "ms"
    end
  end

  # ── Added: pinning documented defaults and boundaries ──────────────────────

  describe "assert_recent/2 default tolerance" do
    test "default tolerance is exactly 5 seconds: 5s old passes" do
      five_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -5, :second])
      assert_recent(five_seconds_ago)
    end

    test "default tolerance is exactly 5 seconds: 6s old fails" do
      six_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -6, :second])

      result =
        try do
          assert_recent(six_seconds_ago)
          :no_failure
        rescue
          ExUnit.AssertionError -> :failed
        end

      assert result == :failed
    end
  end

  describe "assert_recent/2 inclusive comparison" do
    test "a difference exactly equal to the tolerance passes" do
      three_seconds_ago = apply(DateTime, :add, [DateTime.utc_now(), -3, :second])
      assert_recent(three_seconds_ago, 3)
    end

    test "a tolerance of 0 passes for the current second" do
      assert_recent(apply(DateTime, :utc_now, []), 0)
    end
  end

  describe "assert_eventually/3 defaults" do
    test "timeout defaults to 1000ms and interval to 50ms, both reported" do
      message =
        try do
          assert_eventually(fn -> false end)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message =~ ~r/timeout\D*1000ms/
      assert message =~ ~r/interval\D*50ms/
    end
  end

  describe "assert_eventually/3 success value" do
    test "evaluates to :ok when the condition is satisfied" do
      assert assert_eventually(fn -> 42 end) == :ok
    end
  end

  describe "assert_eventually/3 deadline is checked after each call" do
    test "with a 0ms timeout the function runs exactly once before failing" do
      counter = :counters.new(1, [])

      Enum.each(1..20, fn _ ->
        try do
          assert_eventually(
            fn ->
              :counters.add(counter, 1, 1)
              false
            end,
            0,
            1
          )
        rescue
          ExUnit.AssertionError -> :ok
        end
      end)

      assert :counters.get(counter, 1) == 20
    end

    test "reported elapsed is non-negative and may be 0ms" do
      elapsed_values =
        Enum.map(1..20, fn _ ->
          message =
            try do
              assert_eventually(fn -> false end, 0, 0)
              ""
            rescue
              e in ExUnit.AssertionError -> e.message
            end

          case Regex.run(~r/elapsed\D*(\d+)ms/, message) do
            [_, digits] -> String.to_integer(digits)
            _ -> -1
          end
        end)

      assert Enum.all?(elapsed_values, &(&1 >= 0))
      assert Enum.any?(elapsed_values, &(&1 == 0))
    end
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
