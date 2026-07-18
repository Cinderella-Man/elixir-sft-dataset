# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `alnum_segment` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `Generators` that provides reusable `StreamData` generators for common domain models, intended for use with property-based testing via the `StreamData` and `ExUnitProperties` libraries.

I need these generators in the public API:

- `Generators.user/0`
- `Generators.money/0`
- `Generators.date_range/0`
- `Generators.non_empty_list/1`
- `Generators.one_of_weighted/1`

Every one of these must return a `%StreamData{}` struct so it composes with the standard `StreamData` combinator API (`StreamData.map/2`, `StreamData.bind/2`, `StreamData.list_of/2`, `StreamData.filter/2`, …) and works directly inside `check all` clauses. All constraints must be enforced *structurally*, inside the generator — a consumer must never need to filter, reject, or re-roll a generated value to satisfy the documented contract, and no generator may rely on rejection sampling internally either.

Below is the behavior each generator must exhibit.

## `Generators.user/0`

Produces maps with exactly these five keys and no others:

| key | value |
|---|---|
| `:id` | positive integer (`>= 1`; zero and negatives never occur) |
| `:name` | non-empty string, letters only |
| `:email` | string of the form `"<local>@<domain>.<tld>"` |
| `:age` | integer, `18..120` inclusive |
| `:role` | exactly one of `:admin`, `:editor`, `:viewer` |

Details of the string-shaped fields:

- **`:name`** — between 1 and 50 characters inclusive. Every character is an ASCII letter, either lowercase `a`–`z` or uppercase `A`–`Z`. Mixed case within one name is allowed. No digits, whitespace, punctuation, or non-ASCII characters ever appear. The empty string never occurs, and a name longer than 50 characters never occurs.
- **`:email`** — contains exactly one `@`. The `local` part is everything before the `@`; `domain` and `tld` are the parts before and after the single `.` that follows the `@`. Each of the three segments is between 1 and 20 characters inclusive and drawn only from lowercase `a`–`z` and digits `0`–`9`. No segment is ever empty, so the email never starts with `@`, never has an empty domain, and never ends with `.`. Uppercase letters never appear in an email. The three segments are drawn independently of each other and of `:name`.

The boundary values are all reachable: `:age` can be exactly `18` and exactly `120`; `:name` can be exactly 1 character and exactly 50; each email segment can be exactly 1 character and exactly 20.

## `Generators.money/0`

Produces `%{amount: amount, currency: currency}` maps with exactly those two keys.

- `amount` is an integer in `0..10_000_000` inclusive, representing cents. Negative amounts never occur; `0` and `10_000_000` are both reachable.
- `currency` is one of the strings `"USD"`, `"EUR"`, `"GBP"`, `"JPY"`, `"CHF"` — nothing else.
- The two fields are drawn independently: any currency can pair with any amount.

## `Generators.date_range/0`

Produces `%{start_date: start_date, end_date: end_date}` maps with exactly those two keys.

- Both values are `Date` structs.
- Both fall within the inclusive bounds `~D[2000-01-01]` and `~D[2100-12-31]`. Both endpoints of that window are reachable, and no date outside it is ever produced.
- The range is inclusive and never inverted: `Date.compare(start_date, end_date)` is always `:lt` or `:eq`, never `:gt`. This must hold structurally — pick the start first, then draw the end from the days at or after the start (up to the upper bound) — not by filtering out inverted pairs.
- Both same-day ranges (`start_date == end_date`) and multi-day ranges (`start_date < end_date`) must occur with non-negligible frequency: a sample of a few hundred generated values should reliably contain a healthy number of each. Do not lean on the incidental bias of a wide integer range happening to land on its lower bound — make the same-day case an explicit alternative that is chosen a substantial fraction of the time.
- Note that when `start_date` is exactly `~D[2100-12-31]`, the only possible `end_date` is that same day, so the map is a same-day range.

## `Generators.non_empty_list/1`

`non_empty_list(generator)` is a combinator over *any* `StreamData` generator — one of the ones above, a plain `StreamData` generator, or another composed generator.

- It produces lists whose length is between 1 and 20 inclusive. The empty list is never produced, and a list of 21+ elements is never produced. Both boundary lengths (1 and 20) are reachable.
- The length is chosen first and the list then has exactly that many elements; list length does not silently track `StreamData`'s size parameter.
- Every element is a value the wrapped generator could itself have produced, so `non_empty_list(Generators.user())` yields a list of valid user maps, `non_empty_list(StreamData.integer())` yields a list of integers, and so on. Elements are drawn independently — duplicates within one list are allowed and expected.

## `Generators.one_of_weighted/1`

`one_of_weighted(weighted_list)` takes a list of `{weight, generator}` tuples and produces values drawn from those generators in proportion to their weights.

- Weights are non-negative integers. A generator with weight `w` is selected with probability `w / sum_of_all_weights`; e.g. `[{10, gen_a}, {1, gen_b}]` yields values from `gen_a` roughly ten times as often as from `gen_b`. The proportions need only hold statistically — over a sample of a few hundred values the observed split should clearly track the weights, not match them exactly.
- A weight of `0` means that generator is **never** selected: it contributes nothing to the total weight and none of its values ever appear in the output.
- The generators themselves may be arbitrary — including the other generators in this module — and the values they emit are unchanged by this combinator; it only decides which one to draw from.
- Shrinking must still flow through the chosen underlying generator, so a failing property shrinks toward that generator's own minimal values rather than getting stuck.
- The argument must be a non-empty list. Calling it with `[]`, with a non-list, or with a tuple whose weight is not a non-negative integer is a caller error and may raise (a `FunctionClauseError` is fine) — there is no `{:error, …}` return value anywhere in this module's API. Likewise, a list in which *every* weight is `0` leaves nothing to select from and is allowed to raise; you do not need to special-case it with a friendly message.

## Deliverable

Give me the complete module in a single file, with `@doc`/`@moduledoc` documentation and `@spec`s on the public functions. Use only `stream_data` as an external dependency, no others.

## The module with `alnum_segment` missing

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
    min_day = Date.to_gregorian_days(~D[2000-01-01])
    max_day = Date.to_gregorian_days(~D[2100-12-31])

    SD.bind(SD.integer(min_day..max_day), fn start_day ->
      # Use one_of to split between two explicit branches:
      #   1. same-day (start == end) — guaranteed to appear in every test run
      #   2. any valid end-day in [start_day, max_day] — covers multi-day ranges
      # Relying on bias alone (e.g. integer(0..36524) happening to pick 0) is
      # too probabilistic; with 100 default runs it fails intermittently.
      same_day = SD.constant(start_day)
      any_day = SD.integer(start_day..max_day)

      SD.bind(SD.one_of([same_day, any_day]), fn end_day ->
        SD.constant(%{
          start_date: Date.from_gregorian_days(start_day),
          end_date: Date.from_gregorian_days(end_day)
        })
      end)
    end)
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

  Weights must be non-negative integers; a weight of `0` disables its generator
  entirely. The likelihood of a value being drawn from a particular generator
  equals `weight / sum(all_weights)`.

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

  defp alnum_segment do
    # TODO
  end
end
```

Give me only the complete implementation of `alnum_segment` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
