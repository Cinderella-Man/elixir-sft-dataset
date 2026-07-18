# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `Anonymizer` implemented as a **stateful GenServer** that anonymizes streams of records **concurrently** while guaranteeing referential integrity across every batch it has ever processed.

I need these functions in the public API:
- `Anonymizer.start_link(rules)` — start the server. `rules` is a map whose keys are field-name atoms and whose values are one of:
  - `{:pseudonym, prefix}` — replace the value with a stable sequential pseudonym `"<prefix>_<n>"` (e.g. `"PERSON_1"`), where `n` is assigned per field in first-seen order. The same original value always receives the same pseudonym, even across separate `anonymize/2` calls.
  - `:hash` — replace the value with its SHA-256 hex digest.
  - `:redact` — replace the value with `"[REDACTED]"`.
  Returns `{:ok, pid}`.
- `Anonymizer.anonymize(pid, records)` — transform a list of maps and return the transformed list **in the same order**. Records must be processed concurrently (e.g. with `Task.async_stream`), yet the transformation must remain race-free: within and across calls, identical original values for a pseudonymized field must always map to the identical pseudonym, and distinct values must map to distinct pseudonyms. Fields not named in `rules`, and rule fields missing from a given record, are left untouched.
- `Anonymizer.mapping(pid, field)` — return the current `%{original_value => pseudonym}` table accumulated for a pseudonymized `field`.

Because pseudonym numbering depends on first-seen order under concurrency, the exact number attached to any given value is not required to be deterministic across runs — only referential integrity, uniqueness, the `"<prefix>_<n>"` format, and stable cross-batch consistency are required.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

```elixir
defmodule Anonymizer do
  @moduledoc """
  Stateful, concurrent anonymizer.

  A GenServer holds the accumulated `original -> pseudonym` tables so that
  referential integrity is preserved across every batch. `anonymize/2`
  processes records concurrently with `Task.async_stream` while all pseudonym
  assignment is serialized through the server, keeping it race-free. Supported
  rules: `{:pseudonym, prefix}`, `:hash`, `:redact`. Only OTP/stdlib is used.
  """

  use GenServer

  # --- Public API -------------------------------------------------------------

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(rules) when is_map(rules) do
    GenServer.start_link(__MODULE__, rules)
  end

  @spec anonymize(pid(), [map()]) :: [map()]
  def anonymize(pid, records) when is_list(records) do
    rules = GenServer.call(pid, :get_rules)

    records
    |> Task.async_stream(
      fn record ->
        Enum.reduce(rules, record, fn {field, rule}, acc ->
          case Map.fetch(acc, field) do
            {:ok, value} -> Map.put(acc, field, resolve(pid, field, value, rule))
            :error -> acc
          end
        end)
      end,
      max_concurrency: max(System.schedulers_online(), 2),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, record} -> record end)
  end

  @spec mapping(pid(), atom()) :: map()
  def mapping(pid, field) do
    GenServer.call(pid, {:mapping, field})
  end

  # --- Rule resolution --------------------------------------------------------

  defp resolve(_pid, _field, _value, :redact), do: "[REDACTED]"

  defp resolve(_pid, _field, value, :hash) do
    :crypto.hash(:sha256, to_string(value)) |> Base.encode16(case: :lower)
  end

  defp resolve(pid, field, value, {:pseudonym, prefix}) do
    GenServer.call(pid, {:pseudonym, field, to_string(value), prefix})
  end

  # --- GenServer callbacks ----------------------------------------------------

  @impl true
  def init(rules) do
    {:ok, %{rules: rules, maps: %{}, counters: %{}}}
  end

  @impl true
  def handle_call(:get_rules, _from, state) do
    {:reply, state.rules, state}
  end

  def handle_call({:mapping, field}, _from, state) do
    {:reply, Map.get(state.maps, field, %{}), state}
  end

  def handle_call({:pseudonym, field, value, prefix}, _from, state) do
    field_map = Map.get(state.maps, field, %{})

    case Map.fetch(field_map, value) do
      {:ok, pseudonym} ->
        {:reply, pseudonym, state}

      :error ->
        n = Map.get(state.counters, field, 0) + 1
        pseudonym = "#{prefix}_#{n}"

        state = %{
          state
          | maps: Map.put(state.maps, field, Map.put(field_map, value, pseudonym)),
            counters: Map.put(state.counters, field, n)
        }

        {:reply, pseudonym, state}
    end
  end
end
```

The style review said:

```
The solution is green but does not meet the house style: no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/037_004_stateful_concurrent_consistent_pseudonymizer_01/attempt_0 -->
