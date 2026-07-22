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

  test "timeout failure reports an elapsed time at least as large as the timeout" do
    message =
      try do
        assert_eventually(fn -> false end, 200, 10)
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert String.starts_with?(message, "assert_eventually timed out")

    [_, digits] = Regex.run(~r/elapsed\D*(\d+)ms/, message)

    # The deadline is only checked after a call, so a timeout can never happen
    # before `timeout_ms` of real time has passed: elapsed must be >= 200ms.
    assert String.to_integer(digits) >= 200
  end

  test "a non-datetime value flunks with the documented type message" do
    values = apply(Kernel, :++, [[nil, ~D[2024-01-01]], ["nope", 42]])

    Enum.each(values, fn value ->
      message =
        try do
          assert_recent(value, 5)
          ""
        rescue
          e in ExUnit.AssertionError -> e.message
        end

      assert message ==
               "assert_recent expected a DateTime or NaiveDateTime, got: #{inspect(value)}"
    end)
  end

  test "failure detail restates both ISO-8601 times, the difference and the overshoot" do
    old = apply(DateTime, :add, [DateTime.utc_now(), -100, :second])

    message =
      try do
        assert_recent(old, 5)
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert String.starts_with?(message, "assert_recent failed")
    assert message =~ apply(DateTime, :to_iso8601, [old])
    assert message =~ ~r/current UTC time\D*\d{4}-\d{2}-\d{2}T/
    assert message =~ ~r/tolerance\D*5s/

    [_, digits] = Regex.run(~r/difference\D*(\d+)s/, message)
    assert message =~ "#{String.to_integer(digits) - 5}s outside"
  end

  test "no-error field detail lists every changeset error grouped by field" do
    cs =
      make_changeset(
        email: {"is invalid", []},
        age: {"must be greater than 0", []},
        email: {"has already been taken", []}
      )

    message =
      try do
        assert_changeset_error(cs, :name, "can't be blank")
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    grouped = %{
      email: ["is invalid", "has already been taken"],
      age: ["must be greater than 0"]
    }

    assert message =~ "no errors"
    assert message =~ inspect(grouped)

    empty_message =
      try do
        assert_changeset_error(make_changeset([]), :name, "can't be blank")
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert empty_message =~ "no errors"
    assert empty_message =~ "%{}"
  end

  test "mismatch failure begins with the header and restates field and expected message" do
    cs = make_changeset(name: {"can't be blank", []})

    message =
      try do
        assert_changeset_error(cs, :name, "is too short")
        ""
      rescue
        e in ExUnit.AssertionError -> e.message
      end

    assert String.starts_with?(message, "assert_changeset_error failed")
    assert message =~ ":name"
    assert message =~ ~s("is too short")
  end

  test "an already satisfied condition succeeds even with a zero timeout" do
    assert assert_eventually(fn -> true end, 0, 50) == :ok
    assert assert_eventually(fn -> {:ok, 1} end, 0, 50) == :ok
  end
end
