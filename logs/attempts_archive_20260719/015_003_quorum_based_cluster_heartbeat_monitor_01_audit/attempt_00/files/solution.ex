defmodule ClusterMonitor do
  @moduledoc """
  A singleton `GenServer` that supervises registered *clusters* and decides each
  cluster's `:up`/`:down` status by **quorum**.

  A cluster is a group of independent, zero-arity endpoint functions. On every poll
  the monitor calls all endpoints, counts how many report `:ok`, and sets the status
  to `:up` when that count is at least the configured quorum, otherwise `:down`. The
  status is recomputed fresh on every poll — there is no running consecutive-failure
  counter.

  The process is registered under the module name `ClusterMonitor`, so the
  convenience functions (`register_cluster/4`, `poll/1`, `cluster_state/1`,
  `snapshot/0`, `unregister/1`) take no server argument.

  Each registration is tagged with a generation token (a `t:reference/0`). Scheduled
  poll messages carrying a stale token are ignored, so superseded timer chains from
  replaced or removed registrations never run again.
  """

  use GenServer

  @typedoc "A zero-arity endpoint health check."
  @type check_fun :: (-> :ok | {:error, term()})

  @typedoc "The resulting status of a cluster."
  @type status :: :up | :down

  ## Public API

  @doc """
  Starts and links the singleton monitor.

  `opts` is a keyword list. A `:name` option overrides the registered name, but the
  convenience functions always target `ClusterMonitor`. A freshly started server
  tracks zero clusters.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    {name, rest} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, rest, name: name)
  end

  @doc """
  Registers (or replaces) a cluster named `name`.

  `check_funcs` is a non-empty list of zero-arity functions returning `:ok` or
  `{:error, reason}`. `interval_ms` is a positive integer poll interval. Supported
  `opts`: `:quorum` (positive integer, defaults to a strict majority) and `:notify`
  (a two-arity function invoked on an `:up` -> `:down` transition, defaults to a
  no-op).

  Registration does not poll; the first poll runs one `interval_ms` later. The status
  starts as `:up` with `healthy` equal to `total`. Re-registering replaces the
  configuration and resets the status. Always returns `:ok`.
  """
  @spec register_cluster(term(), [check_fun(), ...], pos_integer(), keyword()) :: :ok
  def register_cluster(name, check_funcs, interval_ms, opts \\ [])
      when is_list(check_funcs) and check_funcs != [] and
             is_integer(interval_ms) and interval_ms > 0 and is_list(opts) do
    :ok = Enum.each(check_funcs, &assert_zero_arity!/1)
    GenServer.call(__MODULE__, {:register, name, check_funcs, interval_ms, opts})
  end

  @doc """
  Performs exactly one poll for `name` immediately, identical to a scheduled tick.

  Returns `{:ok, status}` with the resulting status, or `{:error, :not_found}` if the
  cluster is unknown. Does not alter or reschedule the periodic timer.
  """
  @spec poll(term()) :: {:ok, status()} | {:error, :not_found}
  def poll(name) do
    GenServer.call(__MODULE__, {:poll, name})
  end

  @doc """
  Returns the current state of the registered cluster `name`.

  The map has keys `:status`, `:healthy` and `:total`. Returns `{:error, :not_found}`
  if the cluster is unknown.
  """
  @spec cluster_state(term()) ::
          %{status: status(), healthy: non_neg_integer(), total: pos_integer()}
          | {:error, :not_found}
  def cluster_state(name) do
    GenServer.call(__MODULE__, {:cluster_state, name})
  end

  @doc """
  Returns a map of every registered cluster name to its current status.

  Returns `%{}` when no clusters are registered.
  """
  @spec snapshot() :: %{optional(term()) => status()}
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @doc """
  Removes the cluster `name`.

  Returns `:ok` if the cluster existed, or `{:error, :not_found}` otherwise. After
  removal the cluster's scheduled polls never run again.
  """
  @spec unregister(term()) :: :ok | {:error, :not_found}
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  ## GenServer callbacks

  @impl true
  def init(_opts) do
    {:ok, %{clusters: %{}}}
  end

  @impl true
  def handle_call({:register, name, check_funcs, interval_ms, opts}, _from, state) do
    total = length(check_funcs)
    quorum = Keyword.get(opts, :quorum, div(total, 2) + 1)
    notify = Keyword.get(opts, :notify, fn _name, _healthy -> :ok end)
    gen = make_ref()

    cluster = %{
      check_funcs: check_funcs,
      interval_ms: interval_ms,
      quorum: quorum,
      notify: notify,
      status: :up,
      healthy: total,
      total: total,
      gen: gen
    }

    Process.send_after(self(), {:poll, name, gen}, interval_ms)
    {:reply, :ok, put_in(state.clusters[name], cluster)}
  end

  def handle_call({:poll, name}, _from, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, cluster} ->
        updated = run_poll(cluster, name)
        {:reply, {:ok, updated.status}, put_in(state.clusters[name], updated)}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:cluster_state, name}, _from, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, cluster} ->
        view = %{status: cluster.status, healthy: cluster.healthy, total: cluster.total}
        {:reply, view, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:snapshot, _from, state) do
    view = Map.new(state.clusters, fn {name, cluster} -> {name, cluster.status} end)
    {:reply, view, state}
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, _cluster} ->
        {:reply, :ok, %{state | clusters: Map.delete(state.clusters, name)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:poll, name, gen}, state) do
    case Map.fetch(state.clusters, name) do
      {:ok, %{gen: ^gen} = cluster} ->
        updated = run_poll(cluster, name)
        Process.send_after(self(), {:poll, name, gen}, cluster.interval_ms)
        {:noreply, put_in(state.clusters[name], updated)}

      _other ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  @spec run_poll(map(), term()) :: map()
  defp run_poll(cluster, name) do
    healthy = Enum.count(cluster.check_funcs, fn check -> check.() == :ok end)
    new_status = if healthy >= cluster.quorum, do: :up, else: :down

    if cluster.status == :up and new_status == :down do
      cluster.notify.(name, healthy)
    end

    %{cluster | status: new_status, healthy: healthy}
  end

  @spec assert_zero_arity!(check_fun()) :: :ok
  defp assert_zero_arity!(fun) when is_function(fun, 0), do: :ok
end
