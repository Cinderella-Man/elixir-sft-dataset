# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule SubscriptionAggregate do
  @moduledoc """
  An event-sourced Aggregate for a subscription management domain.
  Maintains independent state and event history for multiple subscription IDs.
  """

  use GenServer

  @type id :: any()
  @type command ::
          {:create, String.t()}
          | {:activate}
          | {:suspend, String.t()}
          | {:cancel}
          | {:reactivate}
  @type event :: %{atom() => any(), type: atom()}
  @type state_map ::
          %{plan: String.t(), status: atom(), reason: String.t() | nil} | nil

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

  # Create
  defp validate_command(nil, {:create, plan_name}) do
    {:ok, [%{type: :subscription_created, plan: plan_name}]}
  end

  defp validate_command(_state, {:create, _plan_name}), do: {:error, :already_exists}

  # Not Found Catch-all
  defp validate_command(nil, _command), do: {:error, :not_found}

  # Activate
  defp validate_command(%{status: :pending}, {:activate}) do
    {:ok, [%{type: :subscription_activated}]}
  end

  defp validate_command(_state, {:activate}), do: {:error, :not_pending}

  # Suspend
  defp validate_command(%{status: :active}, {:suspend, reason}) do
    {:ok, [%{type: :subscription_suspended, reason: reason}]}
  end

  defp validate_command(_state, {:suspend, _reason}), do: {:error, :not_active}

  # Cancel
  # Must fail only if already cancelled; any other existing status may cancel.
  defp validate_command(%{status: :cancelled}, {:cancel}), do: {:error, :already_cancelled}

  defp validate_command(_state, {:cancel}) do
    {:ok, [%{type: :subscription_cancelled}]}
  end

  # Reactivate
  defp validate_command(%{status: :cancelled}, {:reactivate}) do
    {:ok, [%{type: :subscription_reactivated}]}
  end

  defp validate_command(_state, {:reactivate}), do: {:error, :not_cancelled}

  # --- Domain Logic: Event Application ---

  defp apply_event(%{type: :subscription_created, plan: plan}, _nil_state) do
    %{plan: plan, status: :pending, reason: nil}
  end

  defp apply_event(%{type: :subscription_activated}, state) do
    %{state | status: :active}
  end

  defp apply_event(%{type: :subscription_suspended, reason: reason}, state) do
    %{state | status: :suspended, reason: reason}
  end

  defp apply_event(%{type: :subscription_cancelled}, state) do
    %{state | status: :cancelled, reason: nil}
  end

  defp apply_event(%{type: :subscription_reactivated}, state) do
    %{state | status: :active, reason: nil}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule SubscriptionAggregateTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = SubscriptionAggregate.start_link([])
    %{agg: pid}
  end

  # -------------------------------------------------------
  # Creating a subscription
  # -------------------------------------------------------

  test "create produces a :subscription_created event", %{agg: agg} do
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    assert event.type == :subscription_created
  end

  test "state after create has correct plan, status, and reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.plan == "premium"
    assert state.status == :pending
    assert state.reason == nil
  end

  test "creating an already-existing subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    assert {:error, :already_exists} =
             SubscriptionAggregate.execute(agg, "sub:1", {:create, "basic"})
  end

  # -------------------------------------------------------
  # Activating a subscription
  # -------------------------------------------------------

  test "activate moves status to :active", %{agg: agg} do
    # TODO
  end

  test "activate on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
  end

  test "activate on already-active subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:error, :not_pending} = SubscriptionAggregate.execute(agg, "sub:1", {:activate})
  end

  # -------------------------------------------------------
  # Suspending a subscription
  # -------------------------------------------------------

  test "suspend moves status to :suspended with reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})

    assert {:ok, [event]} =
             SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    assert event.type == :subscription_suspended

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :suspended
    assert state.reason == "payment_failed"
  end

  test "suspend on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} =
             SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
  end

  test "suspend on pending subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    assert {:error, :not_active} =
             SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
  end

  # -------------------------------------------------------
  # Cancelling a subscription
  # -------------------------------------------------------

  test "cancel moves status to :cancelled", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert event.type == :subscription_cancelled

    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end

  test "cancel on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
  end

  test "cancel on already-cancelled subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert {:error, :already_cancelled} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
  end

  test "cancel from suspended state succeeds", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "overdue"})
    assert {:ok, _} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})

    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end

  # -------------------------------------------------------
  # Reactivating a subscription
  # -------------------------------------------------------

  test "reactivate moves cancelled subscription to :active", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
    assert event.type == :subscription_reactivated

    state = SubscriptionAggregate.state(agg, "sub:1")
    assert state.status == :active
    assert state.reason == nil
  end

  test "reactivate on non-existent subscription fails", %{agg: agg} do
    assert {:error, :not_found} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
  end

  test "reactivate on active subscription fails", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    assert {:error, :not_cancelled} = SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})
  end

  # -------------------------------------------------------
  # Event history
  # -------------------------------------------------------

  test "events returns full ordered history", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    events = SubscriptionAggregate.events(agg, "sub:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :subscription_created,
             :subscription_activated,
             :subscription_suspended
           ]
  end

  test "failed commands produce no events", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    # Both of the following fail against a :pending subscription and must add no events.
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "reason"})
    SubscriptionAggregate.execute(agg, "sub:1", {:reactivate})

    events = SubscriptionAggregate.events(agg, "sub:1")
    assert length(events) == 1
    assert hd(events).type == :subscription_created
  end

  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert SubscriptionAggregate.events(agg, "nonexistent") == []
  end

  # -------------------------------------------------------
  # State queries
  # -------------------------------------------------------

  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert SubscriptionAggregate.state(agg, "nonexistent") == nil
  end

  # -------------------------------------------------------
  # Aggregate independence
  # -------------------------------------------------------

  test "different aggregate ids are completely independent", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})

    SubscriptionAggregate.execute(agg, "sub:2", {:create, "basic"})

    assert SubscriptionAggregate.state(agg, "sub:1").status == :active
    assert SubscriptionAggregate.state(agg, "sub:2").status == :pending

    assert length(SubscriptionAggregate.events(agg, "sub:1")) == 2
    assert length(SubscriptionAggregate.events(agg, "sub:2")) == 1
  end

  # -------------------------------------------------------
  # Full scenario — replay verification
  # -------------------------------------------------------

  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:create, "gold"})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:activate})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:suspend, "payment_overdue"})
    {:error, :not_active} = SubscriptionAggregate.execute(agg, "a", {:suspend, "duplicate"})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:cancel})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:reactivate})
    {:ok, _} = SubscriptionAggregate.execute(agg, "a", {:cancel})

    state = SubscriptionAggregate.state(agg, "a")
    assert state.plan == "gold"
    assert state.status == :cancelled
    assert state.reason == nil

    events = SubscriptionAggregate.events(agg, "a")
    # 6 successful commands = 6 events
    assert length(events) == 6

    types = Enum.map(events, & &1.type)

    assert types == [
             :subscription_created,
             :subscription_activated,
             :subscription_suspended,
             :subscription_cancelled,
             :subscription_reactivated,
             :subscription_cancelled
           ]
  end

  # -------------------------------------------------------
  # Event content
  # -------------------------------------------------------

  test "events carry relevant data", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})
    SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "payment_failed"})

    [created, activated, suspended] = SubscriptionAggregate.events(agg, "sub:1")

    assert created.type == :subscription_created
    assert Map.has_key?(created, :plan)

    assert activated.type == :subscription_activated

    assert suspended.type == :subscription_suspended
    assert suspended.reason == "payment_failed"
  end

  test "cancel from pending succeeds since only cancelled state blocks cancel", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})

    assert {:ok, [event]} = SubscriptionAggregate.execute(agg, "sub:1", {:cancel})
    assert event.type == :subscription_cancelled
    assert SubscriptionAggregate.state(agg, "sub:1").status == :cancelled
  end

  test "start_link registers the process under the given :name option" do
    name = :"agg_#{System.unique_integer([:positive])}"
    assert {:ok, _pid} = SubscriptionAggregate.start_link(name: name)

    assert {:ok, [event]} = SubscriptionAggregate.execute(name, "sub:1", {:create, "premium"})
    assert event.type == :subscription_created
    assert SubscriptionAggregate.state(name, "sub:1").status == :pending
  end

  test ":subscription_created event :plan key holds the plan name from the command",
       %{agg: agg} do
    assert {:ok, [gold_event]} = SubscriptionAggregate.execute(agg, "sub:1", {:create, "gold"})
    assert gold_event.plan == "gold"

    # A second aggregate created with a different plan carries its own plan name,
    # so the key cannot be a constant.
    assert {:ok, [basic_event]} = SubscriptionAggregate.execute(agg, "sub:2", {:create, "basic"})
    assert basic_event.plan == "basic"

    # The persisted history keeps the same plan value that was returned.
    assert [persisted] = SubscriptionAggregate.events(agg, "sub:1")
    assert persisted.type == :subscription_created
    assert persisted.plan == "gold"
  end

  test ":subscription_suspended event :reason key holds the suspend reason", %{agg: agg} do
    SubscriptionAggregate.execute(agg, "sub:1", {:create, "premium"})
    SubscriptionAggregate.execute(agg, "sub:1", {:activate})

    assert {:ok, [suspended]} =
             SubscriptionAggregate.execute(agg, "sub:1", {:suspend, "card_expired"})

    assert suspended.reason == "card_expired"

    assert [_created, _activated, persisted] = SubscriptionAggregate.events(agg, "sub:1")
    assert persisted.type == :subscription_suspended
    assert persisted.reason == "card_expired"
  end
end
```
