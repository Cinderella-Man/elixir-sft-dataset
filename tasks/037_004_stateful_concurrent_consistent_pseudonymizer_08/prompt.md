# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `start_link` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Write me an Elixir module called `Anonymizer` implemented as a **stateful GenServer** that anonymizes streams of records **concurrently** while guaranteeing referential integrity across every batch it has ever processed.

I need these functions in the public API:
- `Anonymizer.start_link(rules)` — start the server. `rules` is a map whose keys are field-name atoms and whose values are one of:
  - `{:pseudonym, prefix}` — replace the value with a stable sequential pseudonym `"<prefix>_<n>"` (e.g. `"PERSON_1"`), where `n` is assigned per field in first-seen order starting at 1. The same original value always receives the same pseudonym, even across separate `anonymize/2` calls.
  - `:hash` — replace the value with the **lowercase** SHA-256 hex digest of its string form.
  - `:redact` — replace the value with `"[REDACTED]"`.
  Returns `{:ok, pid}`.
- `Anonymizer.anonymize(pid, records)` — transform a list of maps and return the transformed list **in the same order**. Records must be processed concurrently (e.g. with `Task.async_stream`), yet the transformation must remain race-free: within and across calls, identical original values for a pseudonymized field must always map to the identical pseudonym, and distinct values must map to distinct pseudonyms. Distinctness is by the original value itself (not a stringified copy), so e.g. the integer `42` and the string `"42"` are different values and receive different pseudonyms. Fields not named in `rules`, and rule fields missing from a given record, are left untouched (and missing rule fields are not added to the record).
- `Anonymizer.mapping(pid, field)` — return the current `%{original_value => pseudonym}` table accumulated for a pseudonymized `field`, keyed by the original values themselves. Returns an empty map (`%{}`) if no values have been seen for that field yet.

Because pseudonym numbering depends on first-seen order under concurrency, the exact number attached to any given value is not required to be deterministic across runs — only referential integrity, uniqueness, the `"<prefix>_<n>"` format, and stable cross-batch consistency are required. Each pseudonymized field numbers independently using its own prefix.

Use only the Elixir/OTP standard library — no external dependencies. Give me the complete module in a single file.

## The module with `start_link` missing

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

  def start_link(rules) when is_map(rules) do
    # TODO
  end

  @doc """
  Transform a list of maps, returning the transformed list in the same order.

  Records are processed concurrently while pseudonym assignment stays
  race-free and referentially consistent within and across calls. Fields not
  named in the rules, and rule fields missing from a record, are left as-is.
  """
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

  @doc """
  Return the current `%{original_value => pseudonym}` table for `field`.
  """
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
    GenServer.call(pid, {:pseudonym, field, value, prefix})
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

Give me only the complete implementation of `start_link` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
