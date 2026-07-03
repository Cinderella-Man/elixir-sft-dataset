Implement the GenServer `handle_call/3` callback for the `Aggregate` module. It has
three clauses, one per request the public API sends via `GenServer.call/2`. In every
clause the server state is a `store` map keyed by aggregate `id`, where each value is
an instance map of the shape `%{state: state_map | nil, events: [event]}`.

1. `{:execute, id, command}` — Look up the current instance for `id` in `store`,
   defaulting to `%{state: nil, events: []}` when the id is unknown. Validate the
   command against the instance's `state` using `validate_command/2`. On `{:ok,
   new_events}`, fold the new events over the current state with `apply_event/2` (via
   `Enum.reduce/3`) to compute the updated state, append `new_events` to the existing
   history, store the updated instance back under `id`, and reply with
   `{:ok, new_events}` alongside the updated store. On `{:error, reason}`, reply with
   `{:error, reason}` and leave the store unchanged.

2. `{:get_state, id}` — Reply with the current calculated state for `id` (i.e. the
   instance's `:state`), or `nil` when the id or state is absent, leaving the store
   unchanged.

3. `{:get_events, id}` — Reply with the ordered event history for `id` (the instance's
   `:events`), defaulting to an empty list when the id is unknown, leaving the store
   unchanged.

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
    # TODO
  end

  @impl true
  def handle_call({:get_state, id}, _from, store) do
    # TODO
  end

  @impl true
  def handle_call({:get_events, id}, _from, store) do
    # TODO
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