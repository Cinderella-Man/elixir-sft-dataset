# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Generators do
  # Qualify every call explicitly rather than bulk-importing StreamData.
  # A bare `import StreamData` pulls in dozens of functions and can produce
  # hard-to-diagnose compile errors when any of their arities clash with
  # auto-imported Kernel functions — particularly on older OTP releases.
  alias StreamData, as: SD

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def user do
    SD.fixed_map(%{
      id: SD.positive_integer(),
      name: user_name(),
      email: email(),
      age: SD.integer(18..120),
      role: SD.member_of([:admin, :editor, :viewer])
    })
  end

  def money do
    SD.fixed_map(%{
      amount: SD.integer(0..10_000_000),
      currency: SD.member_of(["USD", "EUR", "GBP", "JPY", "CHF"])
    })
  end

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

  def non_empty_list(generator) do
    SD.bind(SD.integer(1..20), fn size ->
      SD.list_of(generator, length: size)
    end)
  end

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
