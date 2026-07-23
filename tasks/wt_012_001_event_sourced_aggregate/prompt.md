# Write the test harness

Module and original specification below. Produce the ExUnit harness that
verifies a correct implementation.

Hard requirements:
- Test module: `<Module>Test`, `use ExUnit.Case, async: false`.
- No `ExUnit.start()` (the evaluator owns startup).
- Self-contained single file: inline any fakes, clock Agents, and helpers.
- Full public API coverage plus the specification's edge cases.
- Compiles with zero warnings (`_`-prefix unused variables; float zero
  matches as `+0.0`/`-0.0`).

## Original specification

# Ticket: `Aggregate` — event-sourced bank account GenServer

Implement an Elixir GenServer module named `Aggregate` that maintains state via event sourcing for a simple bank account domain. Single file. OTP standard library only, no external dependencies.

**Public API**

- `Aggregate.start_link(opts)` — starts the process; must accept a `:name` option for process registration.
- `Aggregate.execute(server, id, command)` — validates `command` against the current state of the aggregate identified by `id`, produces zero or more events, applies them to the state, and persists them to an in-memory list. Returns `{:ok, events}` on success, where `events` is the list of new events produced by that command. Returns `{:error, reason}` on validation failure.
- `Aggregate.state(server, id)` — returns the current state of the aggregate. Returns `nil` if the aggregate has never received a command. Otherwise returns a map with at least `:name`, `:balance`, and `:status` keys (`:status` is `:open` after opening).
- `Aggregate.events(server, id)` — returns the full ordered list of events for that aggregate, oldest first. Returns an empty list if the aggregate has never received a command.

**Commands** (tuples)

- `{:open, account_name}`
- `{:deposit, amount}`
- `{:withdraw, amount}`

**Event-sourcing flow** (per command)

- Validate the command against the current state.
- Produce zero or more event structs/maps.
- Apply the events one by one to the state.
- Append the events to the event history.

**Events**

- Events are maps with at least a `:type` key.
- Use types `:account_opened`, `:amount_deposited`, `:amount_withdrawn`.
- `:account_opened` must include the account name under a `:name` (or `:account_name`) key.
- `:amount_deposited` and `:amount_withdrawn` must include the amount under an `:amount` key.

**Validation — `:open`**

- Fail with `{:error, :already_open}` if the account is already open.

**Validation — `:deposit`**

- Fail with `{:error, :account_not_open}` if the account hasn't been opened yet.
- Amount must be positive, else `{:error, :invalid_amount}`.

**Validation — `:withdraw`**

- Fail with `{:error, :account_not_open}` if the account hasn't been opened.
- Amount must be positive, else `{:error, :invalid_amount}`.
- Fail with `{:error, :insufficient_balance}` if the balance is less than the withdrawal amount.
- Withdrawing exactly the current balance succeeds and leaves the balance at zero.

**Isolation**

- Each aggregate `id` is tracked independently — commands on `"acct:1"` must have no effect on `"acct:2"`.

## Module under test

```elixir
defmodule Aggregate do
  @moduledoc """
  An event-sourced Aggregate for a simple bank account domain.
  Maintains independent state and event history for multiple account IDs.
  """

  use GenServer

  @type id :: any()
  @type command :: {:open, String.t()} | {:deposit, number()} | {:withdraw, number()}
  @type event :: %{atom() => any(), type: atom()}
  @type state_map :: %{name: String.t(), balance: number(), status: :open} | nil

  # --- Public API ---

  @doc "Starts the GenServer process."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc "Validates a command, produces events, updates state, and persists history."
  @spec execute(GenServer.server(), id(), command()) :: {:ok, [event()]} | {:error, atom()}
  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end

  @doc "Returns the current calculated state for a specific aggregate ID."
  @spec state(GenServer.server(), id()) :: state_map()
  def state(server, id) do
    GenServer.call(server, {:get_state, id})
  end

  @doc "Returns the full history of events for a specific aggregate ID."
  @spec events(GenServer.server(), id()) :: [event()]
  def events(server, id) do
    GenServer.call(server, {:get_events, id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(initial_state), do: {:ok, initial_state}

  @impl true
  def handle_call({:execute, id, command}, _from, store) do
    current_instance = Map.get(store, id, %{state: nil, events: []})

    case validate_command(current_instance.state, command) do
      {:ok, new_events} ->
        updated_state = Enum.reduce(new_events, current_instance.state, &apply_event/2)

        updated_instance = %{
          state: updated_state,
          events: current_instance.events ++ new_events
        }

        {:reply, {:ok, new_events}, Map.put(store, id, updated_instance)}

      {:error, reason} ->
        {:reply, {:error, reason}, store}
    end
  end

  @impl true
  def handle_call({:get_state, id}, _from, store) do
    {:reply, get_in(store, [id, :state]), store}
  end

  @impl true
  def handle_call({:get_events, id}, _from, store) do
    history =
      store
      |> Map.get(id, %{})
      |> Map.get(:events, [])

    {:reply, history, store}
  end

  # --- Domain Logic: Command Validation ---

  defp validate_command(nil, {:open, name}) do
    {:ok, [%{type: :account_opened, name: name}]}
  end

  defp validate_command(_state, {:open, _name}), do: {:error, :already_open}

  defp validate_command(nil, _command), do: {:error, :account_not_open}

  defp validate_command(_state, {:deposit, amount}) do
    cond do
      amount <= 0 -> {:error, :invalid_amount}
      true -> {:ok, [%{type: :amount_deposited, amount: amount}]}
    end
  end

  defp validate_command(state, {:withdraw, amount}) do
    cond do
      amount <= 0 -> {:error, :invalid_amount}
      state.balance < amount -> {:error, :insufficient_balance}
      true -> {:ok, [%{type: :amount_withdrawn, amount: amount}]}
    end
  end

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :account_opened, name: name}, _nil_state) do
    %{name: name, balance: 0, status: :open}
  end

  defp apply_event(%{type: :amount_deposited, amount: amount}, state) do
    %{state | balance: state.balance + amount}
  end

  defp apply_event(%{type: :amount_withdrawn, amount: amount}, state) do
    %{state | balance: state.balance - amount}
  end
end
```
