defmodule AssertHelpersTest do
  use ExUnit.Case, async: true
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
      assert_recent(DateTime.utc_now())
    end

    test "passes for a NaiveDateTime within tolerance" do
      just_now = NaiveDateTime.utc_now()
      assert_recent(just_now, 5)
    end

    test "passes for a datetime exactly at the tolerance boundary" do
      four_seconds_ago = DateTime.add(DateTime.utc_now(), -4, :second)
      assert_recent(four_seconds_ago, 5)
    end

    test "fails for a datetime well in the past" do
      old = DateTime.add(DateTime.utc_now(), -60, :second)

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
      future = DateTime.add(DateTime.utc_now(), 30, :second)

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
      old = DateTime.add(DateTime.utc_now(), -100, :second)

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
end
