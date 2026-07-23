defmodule Generators do
  @moduledoc """
  Reusable `StreamData` generators for common domain models.

  Every public function returns a `%StreamData{}` struct, so the generators
  compose with the standard `StreamData` combinator API (`StreamData.map/2`,
  `StreamData.bind/2`, `StreamData.list_of/2`, `StreamData.filter/2`, …) and
  can be used directly inside `check all` clauses from `ExUnitProperties`.

  All documented constraints are enforced *structurally*, inside the
  generators themselves: a consumer never needs to filter, reject, or re-roll
  a generated value, and no generator relies on rejection sampling internally.

      use ExUnitProperties

      property "generated users are always adults" do
        check all user <- Generators.user() do
          assert user.age in 18..120
        end
      end
  """

  # Characters allowed in a `:name`: ASCII letters only (both cases).
  @name_chars [?a..?z, ?A..?Z]

  # Characters allowed in each email segment: lowercase letters and digits.
  @email_chars [?a..?z, ?0..?9]

  # Currencies allowed in `money/0`.
  @currencies ~w(USD EUR GBP JPY CHF)

  # Roles allowed in `user/0`.
  @roles [:admin, :editor, :viewer]

  # Inclusive Gregorian-day bounds for `date_range/0`.
  @min_day Date.to_gregorian_days(~D[2000-01-01])
  @max_day Date.to_gregorian_days(~D[2100-12-31])

  @doc """
  Generates user maps with exactly the keys `:id`, `:name`, `:email`, `:age`
  and `:role`.

    * `:id` — positive integer (`>= 1`).
    * `:name` — non-empty string of 1..50 ASCII letters (`a-z`, `A-Z`).
    * `:email` — string `"<local>@<domain>.<tld>"`, each segment 1..20
      characters drawn from `a-z` and `0-9`.
    * `:age` — integer in `18..120` inclusive.
    * `:role` — one of `:admin`, `:editor`, `:viewer`.

  All boundary values (`age` of `18`/`120`, 1- and 50-character names, 1- and
  20-character email segments) are reachable, and the fields are drawn
  independently of one another.
  """
  @spec user() :: StreamData.t()
  def user do
    StreamData.fixed_map(%{
      id: StreamData.positive_integer(),
      name: name(),
      email: email(),
      age: StreamData.integer(18..120),
      role: StreamData.member_of(@roles)
    })
  end

  @doc """
  Generates money maps `%{amount: amount, currency: currency}`.

    * `amount` — integer in `0..10_000_000` inclusive, representing cents.
    * `currency` — one of `"USD"`, `"EUR"`, `"GBP"`, `"JPY"`, `"CHF"`.

  The two fields are drawn independently, and both amount boundaries (`0` and
  `10_000_000`) are reachable.
  """
  @spec money() :: StreamData.t()
  def money do
    StreamData.fixed_map(%{
      amount: StreamData.integer(0..10_000_000),
      currency: StreamData.member_of(@currencies)
    })
  end

  @doc """
  Generates date-range maps `%{start_date: start_date, end_date: end_date}`.

  Both values are `Date` structs within the inclusive window
  `~D[2000-01-01]..~D[2100-12-31]`. The range is never inverted:
  `Date.compare(start_date, end_date)` is always `:lt` or `:eq`.

  The start date is picked first, then the end date is drawn from the days at
  or after the start (up to the upper bound). Same-day ranges are an explicit
  alternative chosen a substantial fraction of the time, so both same-day and
  multi-day ranges occur with non-negligible frequency.
  """
  @spec date_range() :: StreamData.t()
  def date_range do
    StreamData.bind(StreamData.integer(@min_day..@max_day), fn start_day ->
      same_day = StreamData.constant(start_day)
      later_day = StreamData.integer(start_day..@max_day)
      end_day = StreamData.frequency([{1, same_day}, {1, later_day}])

      StreamData.map(end_day, fn day ->
        %{
          start_date: Date.from_gregorian_days(start_day),
          end_date: Date.from_gregorian_days(day)
        }
      end)
    end)
  end

  @doc """
  Wraps any `StreamData` generator, producing lists of 1..20 elements.

  The length is chosen first (independently of `StreamData`'s size
  parameter), and the list then contains exactly that many elements, each
  drawn independently from `generator`. The empty list is never produced, a
  list of 21+ elements is never produced, and both boundary lengths (1 and
  20) are reachable. Duplicates within a single list are allowed.
  """
  @spec non_empty_list(StreamData.t()) :: StreamData.t()
  def non_empty_list(generator) do
    StreamData.bind(StreamData.integer(1..20), fn length ->
      StreamData.list_of(generator, length: length)
    end)
  end

  @doc """
  Draws from a list of `{weight, generator}` tuples in proportion to weights.

  A generator with weight `w` is selected with probability
  `w / sum_of_all_weights`; a weight of `0` means the generator is never
  selected and contributes nothing to the total. The emitted values are
  unchanged by this combinator, and shrinking flows through the chosen
  underlying generator.

  The argument must be a non-empty list of `{non_neg_integer, StreamData.t}`
  tuples. Passing `[]`, a non-list, or a tuple with an invalid weight is a
  caller error and may raise.
  """
  @spec one_of_weighted([{non_neg_integer(), StreamData.t()}]) :: StreamData.t()
  def one_of_weighted([_ | _] = weighted_list) do
    Enum.each(weighted_list, fn {weight, _generator}
                                when is_integer(weight) and weight >= 0 ->
      :ok
    end)

    StreamData.frequency(weighted_list)
  end

  # A non-empty string of 1..50 ASCII letters.
  @spec name() :: StreamData.t()
  defp name do
    StreamData.string(@name_chars, min_length: 1, max_length: 50)
  end

  # An email `"<local>@<domain>.<tld>"` with independent 1..20-char segments.
  @spec email() :: StreamData.t()
  defp email do
    segment = StreamData.string(@email_chars, min_length: 1, max_length: 20)

    StreamData.map(StreamData.tuple({segment, segment, segment}), fn
      {local, domain, tld} -> "#{local}@#{domain}.#{tld}"
    end)
  end
end