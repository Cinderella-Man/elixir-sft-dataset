Implement the private `validate_command/2` function. It takes the current aggregate
state (either `nil` if the aggregate has never been opened, or a state map with
`:name`, `:balance`, and `:status` keys) and a command tuple, and returns either
`{:ok, events}` — where `events` is a list of event maps (each with at least a
`:type` key) to be applied and persisted — or `{:error, reason}` if the command is
invalid for the current state.

It must enforce these rules:

- `{:open, name}`: If the account has never been opened (state is `nil`), succeed with
  a single `%{type: :account_opened, name: name}` event. If the account is already
  open, fail with `{:error, :already_open}`.
- `{:deposit, amount}`: If the account has not been opened yet, fail with
  `{:error, :account_not_open}`. If `amount` is not positive, fail with
  `{:error, :invalid_amount}`. Otherwise succeed with a single
  `%{type: :amount_deposited, amount: amount}` event.
- `{:withdraw, amount}`: If the account has not been opened yet, fail with
  `{:error, :account_not_open}`. If `amount` is not positive, fail with
  `{:error, :invalid_amount}`. If the current balance is less than `amount`, fail with
  `{:error, :insufficient_balance}`. Otherwise succeed with a single
  `%{type: :amount_withdrawn, amount: amount}` event.

Every non-open command issued against a `nil` (never-opened) state must fail with
`{:error, :account_not_open}`.

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

  defp validate_command(state, command) do
    # TODO
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