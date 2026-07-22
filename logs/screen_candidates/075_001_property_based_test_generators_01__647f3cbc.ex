defmodule Generators do
  @moduledoc """
  Reusable `StreamData` generators for common domain models.

  Every function in this module returns a `%StreamData{}` struct so the
  generators compose freely with the standard `StreamData` combinators and
  can be driven from `ExUnitProperties` `check all` blocks.

  All invariants described for each generator are enforced *inside* the
  generator itself: consumers never need to filter, reject, or post-process
  the values that come out.
  """

  @min_date ~D[2000-01-01]
  @max_date ~D[2100-12-31]

  @currencies ["USD", "EUR", "GBP", "JPY", "CHF"]
  @roles [:admin, :editor, :viewer]

  @doc """
  Generates user maps.

  Each generated value is a map with the keys:

    * `:id` — a positive integer;
    * `:name` — a non-empty, letters-only string of at most 50 characters;
    * `:email` — a string shaped like `"<local>@<domain>.<tld>"` where each
      part is a non-empty lowercase alphanumeric string;
    * `:age` — an integer between 18 and 120 (inclusive);
    * `:role` — one of `:admin`, `:editor`, or `:viewer`.
  """
  @spec user() :: StreamData.t(map())
  def user do
    StreamData.fixed_map(%{
      id: StreamData.positive_integer(),
      name: name_generator(),
      email: email_generator(),
      age: StreamData.integer(18..120),
      role: StreamData.member_of(@roles)
    })
  end

  @doc """
  Generates money maps of the shape `%{amount: amount, currency: currency}`.

  `amount` is a non-negative integer representing cents, ranging from `0` to
  `10_000_000` (inclusive). `currency` is one of `"USD"`, `"EUR"`, `"GBP"`,
  `"JPY"`, or `"CHF"`.
  """
  @spec money() :: StreamData.t(map())
  def money do
    StreamData.fixed_map(%{
      amount: StreamData.integer(0..10_000_000),
      currency: StreamData.member_of(@currencies)
    })
  end

  @doc """
  Generates date-range maps of the shape `%{start_date: start, end_date: end_}`.

  Both values are `Date` structs somewhere in the inclusive interval
  `~D[2000-01-01]` .. `~D[2100-12-31]`, and `start_date` is always less than
  or equal to `end_date`.

  Both same-day ranges (`start_date == end_date`) and multi-day ranges
  (`start_date < end_date`) are produced with non-negligible frequency.
  """
  @spec date_range() :: StreamData.t(map())
  def date_range do
    min_day = Date.to_gregorian_days(@min_date)
    max_day = Date.to_gregorian_days(@max_date)

    StreamData.bind(StreamData.integer(min_day..max_day), fn start_day ->
      end_day_generator =
        StreamData.one_of([
          StreamData.constant(start_day),
          StreamData.integer(start_day..max_day)
        ])

      StreamData.map(end_day_generator, fn end_day ->
        %{
          start_date: Date.from_gregorian_days(start_day),
          end_date: Date.from_gregorian_days(end_day)
        }
      end)
    end)
  end

  @doc """
  Wraps any `generator` into one producing non-empty lists.

  Each generated list holds between 1 and 20 elements (inclusive), every
  element drawn independently from the supplied `generator`.
  """
  @spec non_empty_list(StreamData.t(a)) :: StreamData.t([a]) when a: term()
  def non_empty_list(generator) do
    StreamData.list_of(generator, min_length: 1, max_length: 20)
  end

  @doc """
  Chooses among generators proportionally to integer weights.

  Takes a list of `{weight, generator}` tuples and produces values drawn from
  the generators with a probability proportional to each associated weight.
  """
  @spec one_of_weighted([{pos_integer(), StreamData.t(a)}]) ::
          StreamData.t(a)
        when a: term()
  def one_of_weighted(weighted_list) do
    StreamData.frequency(weighted_list)
  end

  # A non-empty, letters-only string of at most 50 characters.
  @spec name_generator() :: StreamData.t(String.t())
  defp name_generator do
    StreamData.string([?a..?z, ?A..?Z], min_length: 1, max_length: 50)
  end

  # An `"<local>@<domain>.<tld>"` email built from non-empty lowercase
  # alphanumeric parts.
  @spec email_generator() :: StreamData.t(String.t())
  defp email_generator do
    part = StreamData.string([?a..?z, ?0..?9], min_length: 1, max_length: 12)

    StreamData.map(StreamData.tuple({part, part, part}), fn {local, domain, tld} ->
      "#{local}@#{domain}.#{tld}"
    end)
  end
end