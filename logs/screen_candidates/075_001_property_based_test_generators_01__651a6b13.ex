defmodule Generators do
  @moduledoc """
  Reusable `StreamData` generators for common domain models, intended for
  property-based testing with `StreamData` and `ExUnitProperties`.

  Every public function returns a `%StreamData{}` struct, so the generators
  compose directly with the standard `StreamData` combinator API
  (`StreamData.map/2`, `StreamData.bind/2`, `StreamData.list_of/2`, …) and can
  be used inside `check all` clauses.

  All constraints are enforced *structurally*, inside the generators
  themselves. A consumer never has to filter, reject, or re-roll a value to
  satisfy the documented contract, and no generator relies on rejection
  sampling internally.
  """

  # ASCII letters, both cases, used for `:name`.
  @letters Enum.concat(?a..?z, ?A..?Z)

  # Lowercase letters and digits, used for the three email segments.
  @email_chars Enum.concat(?a..?z, ?0..?9)

  # Inclusive day-number bounds for the date-range window.
  @min_days Date.to_gregorian_days(~D[2000-01-01])
  @max_days Date.to_gregorian_days(~D[2100-12-31])

  @doc """
  Generates user maps with exactly the keys `:id`, `:name`, `:email`, `:age`
  and `:role`.

    * `:id` — positive integer (`>= 1`).
    * `:name` — non-empty ASCII-letter string, 1..50 characters, mixed case
      allowed.
    * `:email` — string `"<local>@<domain>.<tld>"` where each segment is
      1..20 characters drawn from lowercase letters and digits.
    * `:age` — integer in `18..120` inclusive.
    * `:role` — one of `:admin`, `:editor`, `:viewer`.

  All string fields and the three email segments are drawn independently.
  """
  @spec user() :: StreamData.t()
  def user do
    StreamData.fixed_map(%{
      id: StreamData.positive_integer(),
      name: name_generator(),
      email: email_generator(),
      age: StreamData.integer(18..120),
      role: StreamData.member_of([:admin, :editor, :viewer])
    })
  end

  @doc """
  Generates money maps `%{amount: amount, currency: currency}` with exactly
  those two keys.

    * `amount` — integer cents in `0..10_000_000` inclusive.
    * `currency` — one of `"USD"`, `"EUR"`, `"GBP"`, `"JPY"`, `"CHF"`.

  The two fields are drawn independently.
  """
  @spec money() :: StreamData.t()
  def money do
    StreamData.fixed_map(%{
      amount: StreamData.integer(0..10_000_000),
      currency: StreamData.member_of(["USD", "EUR", "GBP", "JPY", "CHF"])
    })
  end

  @doc """
  Generates date-range maps `%{start_date: start_date, end_date: end_date}`
  with exactly those two keys.

  Both values are `Date` structs within `~D[2000-01-01]..~D[2100-12-31]`
  inclusive. The range is never inverted: `start_date` is picked first and
  `end_date` is drawn from the days at or after it, so
  `Date.compare(start_date, end_date)` is always `:lt` or `:eq`.

  Same-day ranges are chosen as an explicit alternative a substantial fraction
  of the time, so both same-day and multi-day ranges occur frequently.
  """
  @spec date_range() :: StreamData.t()
  def date_range do
    StreamData.bind(StreamData.integer(@min_days..@max_days), fn start_days ->
      start_date = Date.from_gregorian_days(start_days)

      start_days
      |> end_date_generator(start_date)
      |> StreamData.map(fn end_date ->
        %{start_date: start_date, end_date: end_date}
      end)
    end)
  end

  @doc """
  Wraps any `StreamData` generator into one that produces non-empty lists.

  The list length is chosen first (uniformly in `1..20` inclusive) and the
  resulting list then has exactly that many elements, so the length does not
  silently track `StreamData`'s size parameter. Elements are drawn
  independently from `generator`, so duplicates within a list are allowed.

  The empty list is never produced, and lists of 21+ elements never occur.
  """
  @spec non_empty_list(StreamData.t()) :: StreamData.t()
  def non_empty_list(generator) do
    StreamData.bind(StreamData.integer(1..20), fn length ->
      StreamData.list_of(generator, length: length)
    end)
  end

  @doc """
  Draws from a non-empty list of `{weight, generator}` tuples in proportion to
  the weights.

  A generator with weight `w` is selected with probability `w / total_weight`,
  and a weight of `0` means the generator is never selected. The emitted
  values are unchanged, and shrinking flows through the chosen underlying
  generator.

  Weights must be non-negative integers and the argument must be a non-empty
  list; violating either is a caller error and raises (e.g. a
  `FunctionClauseError`). A list whose weights are all `0` may also raise.
  """
  @spec one_of_weighted([{non_neg_integer(), StreamData.t()}]) :: StreamData.t()
  def one_of_weighted([_ | _] = weighted_list) do
    Enum.each(weighted_list, &validate_weighted_pair!/1)
    StreamData.frequency(weighted_list)
  end

  # -- Private helpers -------------------------------------------------------

  @spec name_generator() :: StreamData.t()
  defp name_generator do
    @letters
    |> StreamData.member_of()
    |> StreamData.list_of(min_length: 1, max_length: 50)
    |> StreamData.map(&List.to_string/1)
  end

  @spec email_generator() :: StreamData.t()
  defp email_generator do
    segments = StreamData.tuple({segment(20), segment(20), segment(20)})

    StreamData.map(segments, fn {local, domain, tld} ->
      local <> "@" <> domain <> "." <> tld
    end)
  end

  @spec segment(pos_integer()) :: StreamData.t()
  defp segment(max_length) do
    @email_chars
    |> StreamData.member_of()
    |> StreamData.list_of(min_length: 1, max_length: max_length)
    |> StreamData.map(&List.to_string/1)
  end

  @spec end_date_generator(integer(), Date.t()) :: StreamData.t()
  defp end_date_generator(start_days, start_date) when start_days == @max_days do
    # At the upper bound, the only valid end date is the same day.
    StreamData.constant(start_date)
  end

  defp end_date_generator(start_days, start_date) do
    later =
      (start_days + 1)..@max_days
      |> StreamData.integer()
      |> StreamData.map(&Date.from_gregorian_days/1)

    StreamData.frequency([
      {1, StreamData.constant(start_date)},
      {1, later}
    ])
  end

  @spec validate_weighted_pair!({non_neg_integer(), StreamData.t()}) :: :ok
  defp validate_weighted_pair!({weight, _generator})
       when is_integer(weight) and weight >= 0 do
    :ok
  end
end