# Fill in the middle: `eff/3`

Implement the private `eff/3` function, the memoized core of effective-status
computation. It has the signature `eff(name, nodes, memo)` where `nodes` is the
`%{name => node}` map and `memo` is a `%{name => status}` cache of
already-computed effective statuses. It returns a `{status, memo}` tuple carrying
the node's effective status together with the (possibly extended) memo.

It must behave as follows:

- If `name` is already present in `memo`, return that cached status paired with
  the unchanged `memo` (`{status, memo}`).
- Otherwise look `name` up in `nodes`:
  - If it is **not** in `nodes` (an unknown dependency), treat it as effectively
    `:up`: return `{:up, memo}` **without** writing anything to `memo`.
  - If it **is** in `nodes`:
    - If the node's own status is `:down`, it is effectively `:down`: memoize that
      (`Map.put(memo, name, :down)`) and return `{:down, memo}`.
    - Otherwise its effective status is determined by its dependencies. Compute it
      with `deps_status(node.depends_on, nodes, memo)` (which threads the memo and
      short-circuits to `:down` as soon as any dependency is effectively `:down`),
      then memoize the resulting status under `name` and return `{status, memo}`.

Follow dependencies transitively via the recursion through `deps_status/3`, and be
careful to thread the `memo` returned from each recursive call into the next so
work is never repeated.

```elixir
defmodule DepMonitor do
  @moduledoc """
  A `GenServer` that monitors a set of services arranged in an acyclic
  dependency graph, modeling cascading outages.

  Each node has its own probe-based health (its *own* status), tracked with a
  consecutive-failure threshold. A node's *effective* status is `:down` when its
  own status is `:down` or when any node it depends on — directly or
  transitively — is effectively `:down`. This captures the reality that when a
  dependency (for example a database) goes down, everything relying on it is
  effectively down too.

  Nodes may be probed manually via `check/2` or automatically on a per-node
  interval. Each node may register an `:on_change` callback that fires whenever
  that node's effective status changes.

  The dependency graph must be acyclic; behavior on a cycle is undefined.
  """

  use GenServer

  @typedoc "A running server: a pid or a registered name."
  @type server :: GenServer.server()

  @typedoc "A node's health status."
  @type status :: :up | :down

  @typedoc "A zero-arity probe returning `:ok` or `{:error, reason}`."
  @type probe :: (-> :ok | {:error, term()})

  # ------------------------------------------------------------------
  # Public API
  # ------------------------------------------------------------------

  @doc """
  Starts the monitor, linked to the caller.

  When `opts` contains a `:name`, it is used for process registration;
  otherwise the process is unregistered. A freshly started server has no nodes.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, opts, name: name)
      :error -> GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Adds (or replaces) a node named `name` with the given zero-arity `probe`.

  Supported `opts`:

    * `:depends_on` — node names this node depends on (default `[]`). Names not
      added are treated as effectively `:up`.
    * `:threshold` — consecutive own-probe failures required before the node's
      own status becomes `:down` (default `3`).
    * `:on_change` — `on_change.(name, new_effective_status)`, called when this
      node's effective status changes (default no-op).
    * `:interval` — positive integer milliseconds to schedule automatic probes
      of this node, or `:manual` (default) for probe-on-demand only.

  A new node starts with own status `:up` and `0` consecutive failures. Adding a
  node never invokes any `:on_change` callback. Re-adding an existing `name`
  replaces its configuration and resets it to the initial state.
  """
  @spec add_node(server(), term(), probe(), keyword()) :: :ok
  def add_node(server, name, probe, opts \\ []) when is_function(probe, 0) do
    GenServer.call(server, {:add_node, name, probe, opts})
  end

  @doc """
  Runs exactly one probe for only `name`, updates its own status, and returns
  `{:ok, effective}` with that node's effective status afterward.

  Returns `{:error, :not_found}` when `name` was never added.
  """
  @spec check(server(), term()) :: {:ok, status()} | {:error, :not_found}
  def check(server, name) do
    GenServer.call(server, {:check, name})
  end

  @doc """
  Returns `{:ok, status}` for the node's own status, or `{:error, :not_found}`.
  """
  @spec direct_status(server(), term()) :: {:ok, status()} | {:error, :not_found}
  def direct_status(server, name) do
    GenServer.call(server, {:direct_status, name})
  end

  @doc """
  Returns `{:ok, status}` for the node's effective status, or
  `{:error, :not_found}`.
  """
  @spec effective_status(server(), term()) :: {:ok, status()} | {:error, :not_found}
  def effective_status(server, name) do
    GenServer.call(server, {:effective_status, name})
  end

  @doc """
  Returns a map of `%{name => effective_status}` for every node, or `%{}` when
  there are no nodes.
  """
  @spec snapshot(server()) :: %{optional(term()) => status()}
  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  # ------------------------------------------------------------------
  # GenServer callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{nodes: %{}}}
  end

  @impl true
  def handle_call({:add_node, name, probe, opts}, _from, state) do
    depends_on = Keyword.get(opts, :depends_on, [])
    threshold = Keyword.get(opts, :threshold, 3)
    on_change = Keyword.get(opts, :on_change, fn _name, _status -> :ok end)
    interval = Keyword.get(opts, :interval, :manual)

    epoch =
      case Map.fetch(state.nodes, name) do
        {:ok, old} -> old.epoch + 1
        :error -> 0
      end

    node = %{
      probe: probe,
      depends_on: depends_on,
      threshold: threshold,
      on_change: on_change,
      interval: interval,
      own_status: :up,
      fail_count: 0,
      epoch: epoch
    }

    nodes = Map.put(state.nodes, name, node)
    schedule_tick(name, interval, epoch)
    {:reply, :ok, %{state | nodes: nodes}}
  end

  def handle_call({:check, name}, _from, state) do
    case do_probe(state, name) do
      {:not_found, state} -> {:reply, {:error, :not_found}, state}
      {:ok, effective, state} -> {:reply, {:ok, effective}, state}
    end
  end

  def handle_call({:direct_status, name}, _from, state) do
    case Map.fetch(state.nodes, name) do
      :error -> {:reply, {:error, :not_found}, state}
      {:ok, node} -> {:reply, {:ok, node.own_status}, state}
    end
  end

  def handle_call({:effective_status, name}, _from, state) do
    case Map.fetch(state.nodes, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, _node} ->
        effective = compute_effective(state.nodes)
        {:reply, {:ok, Map.fetch!(effective, name)}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, compute_effective(state.nodes), state}
  end

  @impl true
  def handle_info({:tick, name, epoch}, state) do
    state =
      case Map.fetch(state.nodes, name) do
        {:ok, node} ->
          if node.epoch == epoch and is_integer(node.interval) do
            {:ok, _effective, state} = do_probe(state, name)
            schedule_tick(name, node.interval, epoch)
            state
          else
            state
          end

        :error ->
          state
      end

    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ------------------------------------------------------------------
  # Internals
  # ------------------------------------------------------------------

  @spec schedule_tick(term(), pos_integer() | :manual, non_neg_integer()) :: :ok
  defp schedule_tick(name, interval, epoch) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), {:tick, name, epoch}, interval)
    :ok
  end

  defp schedule_tick(_name, _interval, _epoch), do: :ok

  @spec do_probe(map(), term()) ::
          {:not_found, map()} | {:ok, status(), map()}
  defp do_probe(state, name) do
    case Map.fetch(state.nodes, name) do
      :error ->
        {:not_found, state}

      {:ok, node} ->
        old_effective = compute_effective(state.nodes)
        new_node = apply_result(node, node.probe.())
        nodes = Map.put(state.nodes, name, new_node)
        new_effective = compute_effective(nodes)
        notify_changes(nodes, old_effective, new_effective)
        {:ok, Map.fetch!(new_effective, name), %{state | nodes: nodes}}
    end
  end

  @spec apply_result(map(), :ok | {:error, term()}) :: map()
  defp apply_result(node, :ok) do
    own_status = if node.own_status == :down, do: :up, else: node.own_status
    %{node | fail_count: 0, own_status: own_status}
  end

  defp apply_result(node, {:error, _reason}) do
    count = node.fail_count + 1

    own_status =
      if count >= node.threshold and node.own_status == :up do
        :down
      else
        node.own_status
      end

    %{node | fail_count: count, own_status: own_status}
  end

  @spec notify_changes(map(), map(), map()) :: :ok
  defp notify_changes(nodes, old_effective, new_effective) do
    Enum.each(new_effective, fn {name, status} ->
      if Map.get(old_effective, name) != status do
        node = Map.fetch!(nodes, name)
        node.on_change.(name, status)
      end
    end)
  end

  @spec compute_effective(map()) :: %{optional(term()) => status()}
  defp compute_effective(nodes) do
    Enum.reduce(Map.keys(nodes), %{}, fn name, memo ->
      {_status, memo} = eff(name, nodes, memo)
      memo
    end)
  end

  defp eff(name, nodes, memo) do
    # TODO
  end

  @spec deps_status([term()], map(), map()) :: {status(), map()}
  defp deps_status(deps, nodes, memo) do
    Enum.reduce_while(deps, {:up, memo}, fn dep, {_status, memo} ->
      case eff(dep, nodes, memo) do
        {:down, memo} -> {:halt, {:down, memo}}
        {:up, memo} -> {:cont, {:up, memo}}
      end
    end)
  end
end
```