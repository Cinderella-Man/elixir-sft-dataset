# Task: Implement `handle_call/3` for the `Anonymizer` GenServer

Implement the GenServer `handle_call/3` callback for the `Anonymizer` module below.
It is the synchronization point that keeps concurrent anonymization race-free: every
pseudonym assignment is serialized through these calls. Your implementation must handle
three distinct request messages (one clause each) and, for each, return a
`{:reply, reply, new_state}` tuple.

The server state is a map of the form
`%{rules: rules, maps: %{field => %{original => pseudonym}}, counters: %{field => integer}}`.

Handle these messages:

1. `:get_rules` — reply with the `rules` map held in state; leave the state unchanged.

2. `{:mapping, field}` — reply with the accumulated `%{original_value => pseudonym}`
   table for `field` (an empty map if that field has none yet); leave the state unchanged.

3. `{:pseudonym, field, value, prefix}` — resolve a stable pseudonym for `value` within
   `field`:
   - Look up `value` in that field's mapping table.
   - If it is already present, reply with the existing pseudonym and leave the state
     unchanged (this guarantees referential integrity within and across batches).
   - If it is absent, compute the next number `n` for the field as the field's current
     counter plus one, build the pseudonym `"<prefix>_<n>"`, store the new
     `value => pseudonym` entry in that field's table, update the field's counter to `n`,
     and reply with the new pseudonym alongside the updated state. Distinct values must
     therefore receive distinct, sequentially numbered pseudonyms.

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
  def handle_call(request, from, state) do
    # TODO
  end
end
```