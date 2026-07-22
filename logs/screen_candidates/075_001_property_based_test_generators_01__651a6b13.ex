defmodule Generators do
  @moduledoc """
  Reusable `StreamData` generators for common domain models.

  Every public function returns a `%StreamData{}` struct, so the generators compose
  with the standard `StreamData` combinator API (`StreamData.map/2`,
  `StreamData.bind/2`, `StreamData.list_of/2`, …) and can be used directly inside
  `ExUnitProperties.check/2` (`check all`) clauses.

  All documented constraints are enforced *structurally*: no generator here relies on
  rejection sampling (filtering / re-rolling), and no consumer ever needs to filter a
  generated value to satisfy a contract.

  ## Examples

      use ExUnitProperties

      check all user <- Generators.user() do
        assert user.age in 18..120
      end

  """

  @roles [:admin, :editor, :viewer]

  @currencies ["USD", "EUR", "GBP", "JPY", "CHF"]

  @max_amount 10_000_000

  @min_date ~D[2000-01-01]
  @max_date ~D[2100-12-31]

  # Precomputed Gregorian day numbers for the date window bounds.
  @min_days Date.to_gregorian_days(~D[2000-01-01])
  @max_days Date.to_gregorian_days(~D[2100-12-31])

  @name_max_length 50
  @email_segment_max_length 20

  @max_list_length 20

  @typedoc "A generated user map."
  @type user :: %{
          id: pos_integer(),
          name: String.t(),
          email: String.t(),
          age: 18..120,
          role: :admin | :editor | :viewer
        }

  @typedoc "A generated money map; `:amount` is expressed in cents."
  @type money :: %{amount: non_neg_integer(), currency: String.t()}

  @typedoc "A generated, non-inverted, inclusive date range."
  @type date_range :: %{start_date: Date.t(), end_date: Date.t()}

  @doc """
  Generates user maps with exactly the keys `:id`, `:name`, `:email`, `:age` and `:role`.

    * `:id` — a positive integer (`>= 1`).
    * `:name` — a 1..50 character string of ASCII letters (`a-z`, `A-Z`), mixed case allowed.
    * `:email` — `"<local>@<domain>.<tld>"` where each segment is 1..20 characters drawn
      from lowercase letters and digits.
    * `:age` — an integer in `18..120` inclusive.
    * `:role` — one of `:admin`, `:editor`, `:viewer`.

  All fields are drawn independently of each other.

  ## Examples

      iex> user = Enum.at(StreamData.__struct__(), 0) && :ok
      iex> user
      :ok

  """
  @spec user() :: StreamData.t(user())
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
  Generates money maps with exactly the keys `:amount` and `:currency`.

    * `:amount` — an integer number of cents in `0..10_000_000` inclusive.
    * `:currency` — one of `"USD"`, `"EUR"`, `"GBP"`, `"JPY"`, `"CHF"`.

  The two fields are drawn independently, so any currency may pair with any amount.
  """
  @spec money() :: StreamData.t(money())
  def money do
    StreamData.fixed_map(%{
      amount: StreamData.integer(0..@max_amount),
      currency: StreamData.member_of(@currencies)
    })
  end

  @doc """
  Generates inclusive, never-inverted date ranges.

  Both `:start_date` and `:end_date` are `Date` structs inside the inclusive window
  `~D[2000-01-01]..~D[2100-12-31]`, and `Date.compare(start_date, end_date)` is always
  `:lt` or `:eq`.

  The ordering is structural: the start date is drawn first, then the end date is drawn
  from the days at or after it (bounded above by `~D[2100-12-31]`). Same-day ranges are an
  explicit alternative chosen roughly a third of the time, so both same-day and multi-day
  ranges appear frequently in any reasonably sized sample.
  """
  @spec date_range() :: StreamData.t(date_range())
  def date_range do
    StreamData.bind(StreamData.integer(@min_days..@max_days), fn start_days ->
      start_date = Date.from_gregorian_days(start_days)

      end_days_generator =
        StreamData.frequency([
          {1, StreamData.constant(start_days)},
          {2, StreamData.integer(start_days..@max_days)}
        ])

      StreamData.map(end_days_generator, fn end_days ->
        %{start_date: start_date, end_date: Date.from_gregorian_days(end_days)}
      end)
    end)
  end

  @doc """
  Wraps any `StreamData` generator into one producing non-empty lists of its values.

  The generated lists have a length between 1 and 20 inclusive; the empty list and lists
  of 21 or more elements are never produced. The length is drawn first and the list then
  contains exactly that many independently drawn elements, so list length never silently
  tracks the `StreamData` size parameter.

  ## Examples

      Generators.non_empty_list(Generators.user())
      Generators.non_empty_list(StreamData.integer())

  """
  @spec non_empty_list(StreamData.t(a)) :: StreamData.t(nonempty_list(a)) when a: term()
  def non_empty_list(%StreamData{} = generator) do
    StreamData.bind(StreamData.integer(1..@max_list_length), fn length ->
      StreamData.list_of(generator, length: length)
    end)
  end

  @doc """
  Draws from a list of `{weight, generator}` tuples in proportion to the weights.

  A generator with weight `w` is selected with probability `w / sum_of_all_weights`, so
  `[{10, gen_a}, {1, gen_b}]` yields values from `gen_a` roughly ten times as often as
  from `gen_b`. A weight of `0` means the generator is never selected. Values emitted by
  the chosen generator are passed through unchanged, and shrinking flows through it.

  The argument must be a non-empty list of `{non_neg_integer, StreamData.t/1}` tuples;
  anything else (including a list whose weights are all `0`) is a caller error and raises.

  ## Examples

      Generators.one_of_weighted([{10, Generators.user()}, {1, Generators.money()}])

  """
  @spec one_of_weighted([{non_neg_integer(), StreamData.t(a)}, ...]) :: StreamData.t(a)
        when a: term()
  def one_of_weighted([_ | _] = weighted_generators) do
    weighted_generators
    |> Enum.map(fn {weight, %StreamData{} = generator}
                   when is_integer(weight) and weight >= 0 ->
      {weight, generator}
    end)
    |> StreamData.frequency()
  end

  ## Private helpers

  # 1..50 characters, ASCII letters only, mixed case allowed.
  defp name do
    StreamData.bind(StreamData.integer(1..@name_max_length), fn length ->
      StreamData.string(letter_alphabet(), length: length)
    end)
  end

  # "<local>@<domain>.<tld>", each segment 1..20 lowercase alphanumeric characters.
  defp email do
    segment = email_segment()

    StreamData.map(
      StreamData.tuple({segment, segment, segment}),
      fn {local, domain, tld} -> "#{local}@#{domain}.#{tld}" end
    )
  end

  defp email_segment do
    StreamData.bind(StreamData.integer(1..@email_segment_max_length), fn length ->
      StreamData.string(email_alphabet(), length: length)
    end)
  end

  defp letter_alphabet, do: Enum.concat(?a..?z, ?A..?Z)

  defp email_alphabet, do: Enum.concat(?a..?z, ?0..?9)
end