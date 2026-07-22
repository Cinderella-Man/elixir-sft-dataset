defmodule GeneratorsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp valid_email?(email) do
    case String.split(email, "@") do
      [local, rest] ->
        case String.split(rest, ".") do
          [domain, tld] ->
            Enum.all?([local, domain, tld], fn part ->
              part != "" and String.match?(part, ~r/^[a-z0-9]+$/)
            end)

          _ ->
            false
        end

      _ ->
        false
    end
  end

  # -------------------------------------------------------
  # Generators.user/0
  # -------------------------------------------------------

  describe "Generators.user/0" do
    property "always produces a map with all required keys" do
      check all(user <- Generators.user()) do
        assert is_map(user)
        assert Map.has_key?(user, :id)
        assert Map.has_key?(user, :name)
        assert Map.has_key?(user, :email)
        assert Map.has_key?(user, :age)
        assert Map.has_key?(user, :role)
      end
    end

    property ":id is always a positive integer" do
      check all(user <- Generators.user()) do
        assert is_integer(user.id)
        assert user.id > 0
      end
    end

    property ":name is a non-empty letters-only string of max 50 chars" do
      check all(user <- Generators.user()) do
        assert is_binary(user.name)
        assert String.length(user.name) >= 1
        assert String.length(user.name) <= 50
        assert String.match?(user.name, ~r/^[a-zA-Z]+$/)
      end
    end

    property ":email is always a valid email-shaped string" do
      check all(user <- Generators.user()) do
        assert valid_email?(user.email)
      end
    end

    property ":age is always between 18 and 120" do
      check all(user <- Generators.user()) do
        assert user.age >= 18
        assert user.age <= 120
      end
    end

    property ":role is always one of the allowed atoms" do
      check all(user <- Generators.user()) do
        assert user.role in [:admin, :editor, :viewer]
      end
    end

    property "produces diverse roles across many samples" do
      roles =
        Enum.map(1..300, fn _ ->
          [user] = Enum.take(Generators.user(), 1)
          user.role
        end)

      assert :admin in roles
      assert :editor in roles
      assert :viewer in roles
    end
  end

  # -------------------------------------------------------
  # Generators.money/0
  # -------------------------------------------------------

  describe "Generators.money/0" do
    property "always produces a map with :amount and :currency" do
      check all(m <- Generators.money()) do
        assert Map.has_key?(m, :amount)
        assert Map.has_key?(m, :currency)
      end
    end

    property ":amount is always a non-negative integer within bounds" do
      check all(m <- Generators.money()) do
        assert is_integer(m.amount)
        assert m.amount >= 0
        assert m.amount <= 10_000_000
      end
    end

    property ":currency is always one of the allowed currency codes" do
      check all(m <- Generators.money()) do
        assert m.currency in ["USD", "EUR", "GBP", "JPY", "CHF"]
      end
    end

    property "produces all currencies across many samples" do
      currencies =
        Enum.map(1..300, fn _ ->
          [m] = Enum.take(Generators.money(), 1)
          m.currency
        end)

      for c <- ["USD", "EUR", "GBP", "JPY", "CHF"] do
        assert c in currencies, "Expected currency #{c} to appear in 300 samples"
      end
    end
  end

  # -------------------------------------------------------
  # Generators.date_range/0
  # -------------------------------------------------------

  describe "Generators.date_range/0" do
    property "always produces a map with :start_date and :end_date" do
      check all(dr <- Generators.date_range()) do
        assert Map.has_key?(dr, :start_date)
        assert Map.has_key?(dr, :end_date)
      end
    end

    property "start_date and end_date are always Date structs" do
      check all(dr <- Generators.date_range()) do
        assert %Date{} = dr.start_date
        assert %Date{} = dr.end_date
      end
    end

    property "start_date is always <= end_date" do
      check all(dr <- Generators.date_range()) do
        assert Date.compare(dr.start_date, dr.end_date) in [:lt, :eq]
      end
    end

    property "dates are always within the allowed range" do
      min = ~D[2000-01-01]
      max = ~D[2100-12-31]

      check all(dr <- Generators.date_range()) do
        assert Date.compare(dr.start_date, min) in [:gt, :eq]
        assert Date.compare(dr.end_date, max) in [:lt, :eq]
      end
    end

    property "produces same-day ranges (start == end) and multi-day ranges" do
      comparisons =
        Enum.map(1..500, fn _ ->
          [dr] = Enum.take(Generators.date_range(), 1)
          Date.compare(dr.start_date, dr.end_date)
        end)

      assert :eq in comparisons, "Expected some same-day ranges"
      assert :lt in comparisons, "Expected some multi-day ranges"
    end
  end

  # -------------------------------------------------------
  # Generators.non_empty_list/1
  # -------------------------------------------------------

  describe "Generators.non_empty_list/1" do
    property "always produces a list with at least one element" do
      check all(list <- Generators.non_empty_list(StreamData.integer())) do
        assert is_list(list)
        assert length(list) >= 1
      end
    end

    property "never produces a list with more than 20 elements" do
      check all(list <- Generators.non_empty_list(StreamData.integer())) do
        assert length(list) <= 20
      end
    end

    property "all elements satisfy the inner generator's constraints" do
      check all(list <- Generators.non_empty_list(Generators.money())) do
        for m <- list do
          assert m.amount >= 0
          assert m.currency in ["USD", "EUR", "GBP", "JPY", "CHF"]
        end
      end
    end

    property "works with Generators.user() as the inner generator" do
      check all(list <- Generators.non_empty_list(Generators.user())) do
        assert length(list) >= 1
        assert length(list) <= 20

        for user <- list do
          assert is_integer(user.id) and user.id > 0
          assert user.age >= 18
        end
      end
    end

    property "produces diverse lengths across many samples" do
      lengths =
        Enum.map(1..200, fn _ ->
          [list] = Enum.take(Generators.non_empty_list(StreamData.integer()), 1)
          length(list)
        end)

      assert Enum.min(lengths) == 1
      assert Enum.max(lengths) > 1
    end
  end

  # -------------------------------------------------------
  # Generators.one_of_weighted/1
  # -------------------------------------------------------

  describe "Generators.one_of_weighted/1" do
    property "only produces values from the given generators" do
      gen =
        Generators.one_of_weighted([
          {1, StreamData.constant(:rare)},
          {9, StreamData.constant(:common)}
        ])

      check all(value <- gen) do
        assert value in [:rare, :common]
      end
    end

    test "heavily weighted generator dominates output" do
      gen =
        Generators.one_of_weighted([
          {1, StreamData.constant(:rare)},
          {99, StreamData.constant(:common)}
        ])

      values = Enum.take(gen, 1_000)
      common_count = Enum.count(values, &(&1 == :common))

      # With 99:1 weighting, at least 90% should be :common
      assert common_count >= 900,
             "Expected >= 900 :common out of 1000, got #{common_count}"
    end

    test "a weight of 0 means a generator is never selected" do
      gen =
        Generators.one_of_weighted([
          {0, StreamData.constant(:never)},
          {1, StreamData.constant(:always)}
        ])

      values = Enum.take(gen, 100)
      assert Enum.all?(values, &(&1 == :always))
    end

    property "works with complex domain generators" do
      gen =
        Generators.one_of_weighted([
          {1, Generators.user()},
          {1, Generators.money()}
        ])

      check all(value <- gen) do
        assert is_map(value)
        assert Map.has_key?(value, :id) or Map.has_key?(value, :amount)
      end
    end
  end

  # -------------------------------------------------------
  # Composability
  # -------------------------------------------------------

  describe "composability with StreamData" do
    property "user generator can be filtered with StreamData.filter" do
      check all(user <- StreamData.filter(Generators.user(), &(&1.role == :admin))) do
        assert user.role == :admin
      end
    end

    property "money generator can be mapped" do
      check all(m <- StreamData.map(Generators.money(), & &1.amount)) do
        assert is_integer(m)
        assert m >= 0
      end
    end

    property "date_range can be used inside a list_of" do
      check all(ranges <- StreamData.list_of(Generators.date_range(), length: 3)) do
        assert length(ranges) == 3

        for dr <- ranges do
          assert Date.compare(dr.start_date, dr.end_date) in [:lt, :eq]
        end
      end
    end

    property "non_empty_list works with one_of_weighted" do
      gen =
        Generators.non_empty_list(
          Generators.one_of_weighted([
            {3, Generators.money()},
            {1, StreamData.constant(%{amount: 0, currency: "USD"})}
          ])
        )

      check all(list <- gen) do
        assert length(list) >= 1

        for item <- list do
          assert item.amount >= 0
          assert item.currency in ["USD", "EUR", "GBP", "JPY", "CHF"]
        end
      end
    end
  end

  # -------------------------------------------------------
  # Added: boundary + alphabet reachability
  #
  # These pin the exact documented bounds (18..120, 1..50 name chars,
  # 1..20 email-segment chars, 1..20 list length, amount low bound 0)
  # and the exact documented character sets (a-z / A-Z for names,
  # a-z / 0-9 for emails). Every assertion below restates a bound or a
  # character-set endpoint that the task prompt explicitly calls reachable.
  # -------------------------------------------------------

  defp sample(generator, count), do: Enum.take(generator, count)

  defp email_segments(email) do
    [local, rest] = String.split(email, "@")
    [domain, tld] = String.split(rest, ".")
    [local, domain, tld]
  end

  describe "documented boundaries are exactly reachable" do
    test ":age hits both 18 and 120 and never falls outside 18..120" do
      ages = Generators.user() |> sample(2_000) |> Enum.map(& &1.age)

      # 18 reachable, 120 reachable, and nothing below 18 or above 120.
      assert Enum.min(ages) == 18
      assert Enum.max(ages) == 120
    end

    test ":name hits both the 1-character and 50-character length bounds" do
      lengths =
        Generators.user()
        |> sample(1_000)
        |> Enum.map(&String.length(&1.name))

      assert Enum.min(lengths) == 1
      assert Enum.max(lengths) == 50
    end

    test ":name draws from the full a-z and A-Z alphabet" do
      chars =
        Generators.user()
        |> sample(500)
        |> Enum.flat_map(&String.to_charlist(&1.name))
        |> MapSet.new()

      for c <- [?a, ?z, ?A, ?Z] do
        assert c in chars, "Expected letter #{<<c>>} to appear in generated names"
      end
    end

    test ":email segments hit both the 1-character and 20-character length bounds" do
      lengths =
        Generators.user()
        |> sample(1_000)
        |> Enum.flat_map(&email_segments(&1.email))
        |> Enum.map(&String.length/1)

      assert Enum.min(lengths) == 1
      assert Enum.max(lengths) == 20
    end

    test ":email draws from the full a-z and 0-9 alphabet" do
      chars =
        Generators.user()
        |> sample(500)
        |> Enum.flat_map(fn user ->
          user.email |> email_segments() |> Enum.join() |> String.to_charlist()
        end)
        |> MapSet.new()

      for c <- [?a, ?z, ?0, ?9] do
        assert c in chars, "Expected character #{<<c>>} to appear in generated emails"
      end
    end

    test ":amount is reachable at its documented lower bound of 0" do
      # 0 is far too rare to sample out of 0..10_000_000, but it is the
      # minimum of the documented range, so shrinking must land on it.
      amounts = StreamData.map(Generators.money(), & &1.amount)

      options = [initial_seed: {1, 2, 3}, max_runs: 20, max_shrinking_steps: 10_000]

      {:error, %{shrunk_failure: shrunk}} =
        StreamData.check_all(amounts, options, fn amount -> {:error, amount} end)

      assert shrunk == 0
    end

    test "non_empty_list/1 hits both the length-1 and length-20 bounds" do
      lengths =
        StreamData.integer()
        |> Generators.non_empty_list()
        |> sample(500)
        |> Enum.map(&length/1)

      assert Enum.min(lengths) == 1
      assert Enum.max(lengths) == 20
    end
  end

  # -------------------------------------------------------
  # Exact map shapes
  #
  # The documented maps carry exactly the listed keys and no others, so
  # an extra field (e.g. :created_at) is a contract violation even though
  # every documented key is still present.
  # -------------------------------------------------------

  describe "generated maps carry exactly the documented keys" do
    property "user/0 maps have exactly :id, :name, :email, :age and :role" do
      check all(user <- Generators.user()) do
        assert map_size(user) == 5
        assert Enum.sort(Map.keys(user)) == [:age, :email, :id, :name, :role]
      end
    end

    property "money/0 maps have exactly :amount and :currency" do
      check all(m <- Generators.money()) do
        assert map_size(m) == 2
        assert Enum.sort(Map.keys(m)) == [:amount, :currency]
      end
    end

    property "date_range/0 maps have exactly :start_date and :end_date" do
      check all(dr <- Generators.date_range()) do
        assert map_size(dr) == 2
        assert Enum.sort(Map.keys(dr)) == [:end_date, :start_date]
      end
    end
  end

  # -------------------------------------------------------
  # Shrinking through one_of_weighted/1
  #
  # The combinator only decides which generator to draw from; a failing
  # property must still shrink toward the chosen generator's own minimal
  # value rather than getting stuck on whatever value was first drawn.
  # -------------------------------------------------------

  describe "one_of_weighted/1 preserves shrinking" do
    defp always_failing_shrink(generator, seed) do
      options = [initial_seed: seed, max_runs: 20, max_shrinking_steps: 10_000]

      {:error, %{shrunk_failure: shrunk}} =
        StreamData.check_all(generator, options, fn value -> {:error, value} end)

      shrunk
    end

    test "a single weighted generator shrinks toward its own minimal value" do
      gen = Generators.one_of_weighted([{1, StreamData.integer(100..1_000)}])

      assert always_failing_shrink(gen, {7, 8, 9}) == 100
    end

    test "shrinking flows through whichever weighted generator was chosen" do
      # Both branches bottom out at 50, so whichever one the weights select,
      # a failing property must shrink all the way down to that value.
      gen =
        Generators.one_of_weighted([
          {5, StreamData.integer(50..500)},
          {1, StreamData.integer(50..500)}
        ])

      assert always_failing_shrink(gen, {11, 12, 13}) == 50
    end
  end

  test "date_range/0 yields a healthy number of both same-day and multi-day ranges" do
    comparisons =
      Generators.date_range()
      |> sample(500)
      |> Enum.map(&Date.compare(&1.start_date, &1.end_date))

    same_day = Enum.count(comparisons, &(&1 == :eq))
    multi_day = Enum.count(comparisons, &(&1 == :lt))

    assert same_day >= 50,
           "expected >= 50 same-day ranges out of 500, got #{same_day}"

    assert multi_day >= 50,
           "expected >= 50 multi-day ranges out of 500, got #{multi_day}"
  end

  test "money/0 :amount reaches the top of its documented 0..10_000_000 window" do
    amounts = Generators.money() |> sample(3_000) |> Enum.map(& &1.amount)
    max_amount = Enum.max(amounts)

    # A truncated or size-scaled amount range would never climb this high.
    assert max_amount > 9_900_000,
           "expected amounts near 10_000_000; max of 3000 samples was #{max_amount}"

    assert max_amount <= 10_000_000
    assert Enum.min(amounts) >= 0
  end

  test "date_range/0 can produce the 2000-01-01 endpoint of the documented window" do
    # 2000-01-01 is one draw out of ~36_890 days, far too rare to sample, but it
    # is the minimum of the documented window, so shrinking must land on it.
    shrunk = always_failing_shrink(Generators.date_range(), {21, 22, 23})

    assert shrunk.start_date == ~D[2000-01-01]
    assert shrunk.end_date == ~D[2000-01-01]
  end

  test "one_of_weighted/1 raises for an empty list, a non-list, or a bad weight" do
    assert_raise FunctionClauseError, fn -> Generators.one_of_weighted([]) end

    assert_raise FunctionClauseError, fn -> Generators.one_of_weighted(:not_a_list) end

    assert_raise FunctionClauseError, fn ->
      Generators.one_of_weighted([{-1, StreamData.constant(:x)}])
    end

    assert_raise FunctionClauseError, fn ->
      Generators.one_of_weighted([{1.5, StreamData.constant(:x)}])
    end
  end

  test "non_empty_list/1 allows duplicate elements inside a single list" do
    lists =
      StreamData.member_of([:a, :b])
      |> Generators.non_empty_list()
      |> sample(200)

    assert Enum.any?(lists, fn list -> length(Enum.uniq(list)) < length(list) end),
           "expected at least one list with duplicate elements across 200 samples"
  end

  test "each public generator returns a %StreamData{} struct" do
    assert %StreamData{} = Generators.user()
    assert %StreamData{} = Generators.money()
    assert %StreamData{} = Generators.date_range()
    assert %StreamData{} = Generators.non_empty_list(StreamData.integer())
    assert %StreamData{} = Generators.one_of_weighted([{1, StreamData.constant(:x)}])
  end
end
