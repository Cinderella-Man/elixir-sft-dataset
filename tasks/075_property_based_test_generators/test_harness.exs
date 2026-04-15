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
end
