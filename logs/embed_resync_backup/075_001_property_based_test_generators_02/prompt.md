Implement the public `date_range/0` function. It should return a `%StreamData{}`
generator that produces maps of the shape `%{start_date: Date.t(), end_date: Date.t()}`
where both dates fall within the inclusive bounds `~D[2000-01-01]..~D[2100-12-31]`
and `start_date` is always less than or equal to `end_date`.

Work in terms of Gregorian day counts: compute `min_day` and `max_day` by calling
`Date.to_gregorian_days/1` on the two boundary dates. First bind over an integer in
`min_day..max_day` to pick `start_day`. Then, to guarantee the `start_date <= end_date`
invariant structurally (never by filtering), select `end_day` from a `one_of` of two
explicit branches: a `constant(start_day)` branch (so same-day ranges reliably appear)
and an `integer(start_day..max_day)` branch (for multi-day ranges). Finally, bind over
that choice and return a `constant/1` map built with `Date.from_gregorian_days/1` for
both `start_date` and `end_date`. Qualify all `StreamData` calls through the `SD` alias.

```elixir
defmodule Generators do
  @moduledoc """
  Reusable `StreamData` generators for common domain models, intended for use
  with property-based testing via the `StreamData` and `ExUnitProperties` libraries.

  ## Usage

      use ExUnitProperties

      property "users have valid roles" do
        check all user <- Generators.user() do
          assert user.role in [:admin, :editor, :viewer]
        end
      end

  All generators return `%StreamData{}` structs and are fully composable with
  the standard `StreamData` combinator API (`StreamData.map/2`,
  `StreamData.bind/2`, `StreamData.filter/2`, etc.).
  """

  # Qualify every call explicitly rather than bulk-importing StreamData.
  # A bare `import StreamData` pulls in dozens of functions and can produce
  # hard-to-diagnose compile errors when any of their arities clash with
  # auto-imported Kernel functions — particularly on older OTP releases.
  alias StreamData, as: SD

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Produces maps representing a user domain model.

  ## Shape

      %{
        id:    pos_integer(),
        name:  String.t(),   # letters only, 1–50 chars
        email: String.t(),   # "<local>@<domain>.<tld>"
        age:   integer(),    # 18–120
        role:  :admin | :editor | :viewer
      }

  All constraints are enforced inside the generator; consumers never need to
  call `StreamData.filter/2` to discard values.
  """
  @spec user() :: StreamData.t(map())
  def user do
    SD.fixed_map(%{
      id: SD.positive_integer(),
      name: user_name(),
      email: email(),
      age: SD.integer(18..120),
      role: SD.member_of([:admin, :editor, :viewer])
    })
  end

  @doc """
  Produces maps representing a monetary value.

  ## Shape

      %{
        amount:   non_neg_integer(),  # cents, 0–10_000_000
        currency: String.t()          # "USD" | "EUR" | "GBP" | "JPY" | "CHF"
      }
  """
  @spec money() :: StreamData.t(map())
  def money do
    SD.fixed_map(%{
      amount: SD.integer(0..10_000_000),
      currency: SD.member_of(["USD", "EUR", "GBP", "JPY", "CHF"])
    })
  end

  @doc """
  Produces maps representing an inclusive date range.

  ## Shape

      %{
        start_date: Date.t(),  # within 2000-01-01..2100-12-31
        end_date:   Date.t()   # >= start_date, within the same bounds
      }

  The guarantee `start_date <= end_date` is enforced structurally: the
  end-day range opens at `start_day`, so rejection-filtering is never needed.
  """
  @spec date_range() :: StreamData.t(map())
  def date_range do
    # TODO
  end

  @doc """
  A combinator that wraps any generator and produces non-empty lists of 1–20
  elements drawn from it.

  ## Example

      Generators.non_empty_list(StreamData.integer())
      # => [3, -1, 42, 7]  (between 1 and 20 elements)

      Generators.non_empty_list(Generators.user())
      # => [%{id: 1, name: "Alice", ...}, ...]
  """
  @spec non_empty_list(StreamData.t(a)) :: StreamData.t(nonempty_list(a)) when a: term()
  def non_empty_list(generator) do
    SD.bind(SD.integer(1..20), fn size ->
      SD.list_of(generator, length: size)
    end)
  end

  @doc """
  A combinator that accepts a list of `{weight, generator}` tuples and produces
  values from the generators with probability proportional to each weight.

  Weights must be positive integers. The likelihood of a value being drawn from
  a particular generator equals `weight / sum(all_weights)`.

  ## Example

      Generators.one_of_weighted([
        {10, StreamData.constant(:common)},
        {1,  StreamData.constant(:rare)}
      ])
      # => :common roughly 10× more often than :rare
  """
  @spec one_of_weighted([{pos_integer(), StreamData.t(a)}]) :: StreamData.t(a) when a: term()
  def one_of_weighted(weighted_list) when is_list(weighted_list) and weighted_list != [] do
    # Expand each {weight, gen} pair into `weight` copies of `gen`, then hand
    # off to `StreamData.one_of/1` for uniform selection. This keeps the
    # implementation a single pipeline with no custom sampling math, and
    # correctly propagates shrinking through the underlying generators.
    expanded =
      Enum.flat_map(weighted_list, fn {weight, gen}
                                      when is_integer(weight) and weight >= 0 ->
        # weight 0 → List.duplicate returns [] → generator is never selected
        List.duplicate(gen, weight)
      end)

    SD.one_of(expanded)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Produces a non-empty, letters-only string of at most 50 characters.
  # Draws a length first, then fills exactly that many codepoints from the
  # union of a–z and A–Z, so empty strings and digits are structurally
  # impossible — no filter step required.
  defp user_name do
    letter = SD.member_of(Enum.concat(?a..?z, ?A..?Z))

    SD.bind(SD.integer(1..50), fn length ->
      SD.bind(SD.list_of(letter, length: length), fn codepoints ->
        SD.constant(List.to_string(codepoints))
      end)
    end)
  end

  # Produces a string in the format "<local>@<domain>.<tld>" where each
  # segment is a non-empty lowercase alphanumeric string (1–20 chars).
  defp email do
    SD.bind(alnum_segment(), fn local ->
      SD.bind(alnum_segment(), fn domain ->
        SD.bind(alnum_segment(), fn tld ->
          SD.constant("#{local}@#{domain}.#{tld}")
        end)
      end)
    end)
  end

  # Produces a non-empty lowercase alphanumeric string of 1–20 characters.
  defp alnum_segment do
    lowercase_alnum = SD.member_of(Enum.concat(?a..?z, ?0..?9))

    SD.bind(SD.integer(1..20), fn length ->
      SD.bind(SD.list_of(lowercase_alnum, length: length), fn codepoints ->
        SD.constant(List.to_string(codepoints))
      end)
    end)
  end
end
```