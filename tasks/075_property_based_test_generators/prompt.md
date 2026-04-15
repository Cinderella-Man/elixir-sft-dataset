Write me an Elixir module called `Generators` that provides reusable `StreamData` generators for common domain models, intended for use with property-based testing via the `StreamData` and `ExUnitProperties` libraries.

I need these generators in the public API:

- `Generators.user()` — produces maps with the following keys: `:id` (positive integer), `:name` (non-empty string, letters only, max 50 chars), `:email` (string in the format `"<local>@<domain>.<tld>"` where each part is a non-empty lowercase alphanumeric string), `:age` (integer between 18 and 120), and `:role` (one of `:admin`, `:editor`, `:viewer`).
- `Generators.money()` — produces `%{amount: amount, currency: currency}` maps where `amount` is a non-negative integer (representing cents, 0 to 10_000_000) and `currency` is one of `"USD"`, `"EUR"`, `"GBP"`, `"JPY"`, `"CHF"`.
- `Generators.date_range()` — produces `%{start_date: start, end_date: end_}` maps where both values are `Date` structs in the range `~D[2000-01-01]` to `~D[2100-12-31]`, and `start_date` is always less than or equal to `end_date`.
- `Generators.non_empty_list(generator)` — a combinator that takes any other generator and produces a list of 1 to 20 elements drawn from it.
- `Generators.one_of_weighted(weighted_list)` — takes a list of `{weight, generator}` tuples and produces values from the generators proportional to their weights.

Each generator must be composable with standard `StreamData` combinators (i.e., they return `%StreamData{}` structs). All constraints must be enforced within the generator itself — consumers should never need to filter or reject generated values.

Give me the complete module in a single file. Use only `stream_data` as an external dependency, no others.