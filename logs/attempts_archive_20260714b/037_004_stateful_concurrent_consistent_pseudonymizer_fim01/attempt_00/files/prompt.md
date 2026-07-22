# Task: Implement `resolve/4`

Implement the private `resolve/4` function, the rule-application helper used by
`anonymize/2` to transform a single field value according to its rule. It is
called as `resolve(pid, field, value, rule)` where `pid` is the anonymizer
server, `field` is the field-name atom, `value` is the original field value, and
`rule` is the field's configured rule.

Provide one function clause per rule shape:

- For the `:redact` rule, ignore the pid, field, and value and return the
  constant string `"[REDACTED]"`.
- For the `:hash` rule, ignore the pid and field, compute the SHA-256 digest of
  the value (convert the value to a string first with `to_string/1`) using
  `:crypto.hash(:sha256, ...)`, and return it as a lowercase hexadecimal string
  via `Base.encode16(case: :lower)`.
- For the `{:pseudonym, prefix}` rule, delegate to the server so that pseudonym
  assignment stays serialized and race-free: issue a `GenServer.call/2` with the
  message `{:pseudonym, field, to_string(value), prefix}` and return the
  pseudonym the server replies with. (Convert the value to a string with
  `to_string/1` so the stored key is stable.)

Keep the clauses private (`defp`) and match the argument names/underscore
conventions shown by the skeleton comments.

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

  @doc """
  Start the anonymizer server.

  `rules` is a map of field-name atoms to one of `{:pseudonym, prefix}`,
  `:hash`, or `:redact`. Returns `{:ok, pid}`.
  """
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(rules) when is_map(rules) do
    GenServer.start_link(__MODULE__, rules)
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

  # TODO: implement resolve/4 (one clause per rule: :redact, :hash,
  # and {:pseudonym, prefix}).

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