defmodule Aggregate do
  @moduledoc """
  A GenServer implementing a simple event-sourced bank account aggregate store.

  Each aggregate is identified by an arbitrary `id` term. State is never mutated
  directly by commands: a command is first validated against the current state,
  which yields zero or more events; each event is then applied to the state in
  order, and finally appended to that aggregate's event history.

  Commands:

    * `{:open, account_name}` — opens a new account
    * `{:deposit, amount}` — deposits a positive amount
    * `{:withdraw, amount}` — withdraws a positive amount, up to the balance

  Events are plain maps carrying a `:type` key:

    * `%{type: :account_opened, name: name}`
    * `%{type: :amount_deposited, amount: amount}`
    * `%{type: :amount_withdrawn, amount: amount}`

  Everything is stored in memory, in the GenServer's own state; nothing is
  persisted across restarts.
  """

  use GenServer

  @typedoc "Identifier of an individual aggregate."
  @type id :: term()

  @typedoc "A domain event produced by a successful command."
  @type event :: %{required(:type) => atom(), optional(atom()) => term()}

  @typedoc "The materialised state of a single aggregate."
  @type account :: %{name: String.t(), balance: number(), status: :open}

  @typedoc "A command accepted by `execute/3`."
  @type command ::
          {:open, String.t()}
          | {:deposit, number()}
          | {:withdraw, number()}

  @typedoc "Internal per-aggregate record: current state plus its event history."
  @type record :: %{state: account(), events: [event()]}

  # ── Public API ──────────────────────────────────────────────────────────────

  @doc """
  Starts the aggregate store.

  Supported options:

    * `:name` — a name under which to register the process (any valid
      `t:GenServer.name/0`). All other options are forwarded to `GenServer`.

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name] ++ opts, else: opts
    GenServer.start_link(__MODULE__, :ok, server_opts)
  end

  @doc """
  Validates `command` against the current state of the aggregate `id`, applies
  the resulting events and appends them to the aggregate's history.

  Returns `{:ok, events}` with only the events produced by this command, or
  `{:error, reason}` if validation failed — in which case no state change and no
  history append occur.

  ## Examples

      iex> {:ok, pid} = Aggregate.start_link()
      iex> {:ok, [%{type: :account_opened}]} = Aggregate.execute(pid, "a", {:open, "Ada"})
      iex> Aggregate.execute(pid, "a", {:withdraw, 1})
      {:error, :insufficient_balance}

  """
  @spec execute(GenServer.server(), id(), command()) :: {:ok, [event()]} | {:error, atom()}
  def execute(server, id, command) do
    GenServer.call(server, {:execute, id, command})
  end

  @doc """
  Returns the current state of the aggregate `id`, or `nil` if it has never
  successfully received a command.
  """
  @spec state(GenServer.server(), id()) :: account() | nil
  def state(server, id) do
    GenServer.call(server, {:state, id})
  end

  @doc """
  Returns the full event history of the aggregate `id`, oldest event first.

  Returns `[]` for an unknown aggregate.
  """
  @spec events(GenServer.server(), id()) :: [event()]
  def events(server, id) do
    GenServer.call(server, {:events, id})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────────

  @impl GenServer
  @spec init(:ok) :: {:ok, %{id() => record()}}
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:execute, id, command}, _from, aggregates) do
    record = Map.get(aggregates, id, %{state: nil, events: []})

    case handle_command(command, record.state) do
      {:ok, new_events} ->
        new_state = Enum.reduce(new_events, record.state, &apply_event/2)
        updated = %{state: new_state, events: record.events ++ new_events}
        {:reply, {:ok, new_events}, Map.put(aggregates, id, updated)}

      {:error, reason} ->
        {:reply, {:error, reason}, aggregates}
    end
  end

  def handle_call({:state, id}, _from, aggregates) do
    {:reply, get_in(aggregates, [id, :state]), aggregates}
  end

  def handle_call({:events, id}, _from, aggregates) do
    events = with %{events: events} <- Map.get(aggregates, id), do: events
    {:reply, events || [], aggregates}
  end

  # ── Command handling (validation → events) ──────────────────────────────────

  @spec handle_command(command(), account() | nil) :: {:ok, [event()]} | {:error, atom()}
  defp handle_command({:open, _name}, %{status: :open}), do: {:error, :already_open}

  defp handle_command({:open, name}, nil) do
    {:ok, [%{type: :account_opened, name: name}]}
  end

  defp handle_command({:deposit, _amount}, nil), do: {:error, :account_not_open}

  defp handle_command({:deposit, amount}, %{status: :open}) do
    if positive?(amount) do
      {:ok, [%{type: :amount_deposited, amount: amount}]}
    else
      {:error, :invalid_amount}
    end
  end

  defp handle_command({:withdraw, _amount}, nil), do: {:error, :account_not_open}

  defp handle_command({:withdraw, amount}, %{status: :open, balance: balance}) do
    cond do
      not positive?(amount) -> {:error, :invalid_amount}
      balance < amount -> {:error, :insufficient_balance}
      true -> {:ok, [%{type: :amount_withdrawn, amount: amount}]}
    end
  end

  defp handle_command(_command, _state), do: {:error, :unknown_command}

  @spec positive?(term()) :: boolean()
  defp positive?(amount) when is_number(amount), do: amount > 0
  defp positive?(_amount), do: false

  # ── Event application (events → state) ──────────────────────────────────────

  @spec apply_event(event(), account() | nil) :: account()
  defp apply_event(%{type: :account_opened, name: name}, _state) do
    %{name: name, balance: 0, status: :open}
  end

  defp apply_event(%{type: :amount_deposited, amount: amount}, %{balance: balance} = state) do
    %{state | balance: balance + amount}
  end

  defp apply_event(%{type: :amount_withdrawn, amount: amount}, %{balance: balance} = state) do
    %{state | balance: balance - amount}
  end

  defp apply_event(_event, state), do: state
end