# Migrate existing code to a new spec

Starting point: the working, tested solution below, from a related task.
Change it — no ground-up rewrite — until it satisfies the specification
that follows. On any disagreement between the two (module name, public API,
behavior, constraints, output format), the new specification wins. Output
the complete updated code.

## Existing code (your starting point)

```elixir
defmodule EventBus do
  @moduledoc """
  An in-process pub/sub event bus with wildcard topic support.

  Topics are dot-separated strings (e.g. "orders.created").
  A "*" segment in a subscription pattern matches exactly one segment.
  """

  use GenServer

  # ── Client API ──────────────────────────────────────────────

  @doc "Starts the EventBus. Accepts a `:name` option for registration."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, init_opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, init_opts, server_opts)
  end

  @doc "Subscribes `pid` to `topic`. Returns `{:ok, ref}`."
  @spec subscribe(GenServer.server(), String.t(), pid()) ::
          {:ok, reference()}
  def subscribe(server, topic, pid) do
    GenServer.call(server, {:subscribe, topic, pid})
  end

  @doc "Removes the subscription identified by `ref` from `topic`."
  @spec unsubscribe(GenServer.server(), String.t(), reference()) ::
          :ok
  def unsubscribe(server, topic, ref) do
    GenServer.call(server, {:unsubscribe, topic, ref})
  end

  @doc "Publishes `event` to all subscribers matching `topic`."
  @spec publish(GenServer.server(), String.t(), term()) :: :ok
  def publish(server, topic, event) do
    GenServer.call(server, {:publish, topic, event})
  end

  # ── Server Callbacks ────────────────────────────────────────

  @impl true
  def init(_opts) do
    # topics: %{topic_pattern => %{ref => pid}}
    # refs:   %{ref => {pid, topic_pattern}}
    # pids:   %{pid => MapSet.t(ref)}
    {:ok, %{topics: %{}, refs: %{}, pids: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid}, _from, state) do
    ref = Process.monitor(pid)

    topics =
      Map.update(
        state.topics,
        topic,
        %{ref => pid},
        &Map.put(&1, ref, pid)
      )

    refs = Map.put(state.refs, ref, {pid, topic})

    pids =
      Map.update(
        state.pids,
        pid,
        MapSet.new([ref]),
        &MapSet.put(&1, ref)
      )

    {:reply, {:ok, ref}, %{state | topics: topics, refs: refs, pids: pids}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, drop_subscription(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    message = {:event, topic, event}

    Enum.each(state.topics, fn {pattern, subs} ->
      if topic_matches?(pattern, topic) do
        Enum.each(subs, fn {_ref, pid} ->
          send(pid, message)
        end)
      end
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, down_ref, :process, pid, _reason}, state) do
    case Map.fetch(state.pids, pid) do
      {:ok, ref_set} ->
        Enum.each(ref_set, fn r ->
          if r != down_ref do
            Process.demonitor(r, [:flush])
          end
        end)

        state =
          Enum.reduce(ref_set, state, fn r, acc ->
            case Map.fetch(acc.refs, r) do
              {:ok, {_pid, topic}} ->
                drop_subscription_entry(acc, topic, r)

              :error ->
                acc
            end
          end)

        {:noreply, %{state | pids: Map.delete(state.pids, pid)}}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ── Internal Helpers ────────────────────────────────────────

  defp drop_subscription(state, topic, ref) do
    case Map.fetch(state.refs, ref) do
      {:ok, {pid, ^topic}} ->
        Process.demonitor(ref, [:flush])
        state = drop_subscription_entry(state, topic, ref)
        clean_pid_refs(state, pid, ref)

      _ ->
        state
    end
  end

  defp clean_pid_refs(state, pid, ref) do
    case Map.fetch(state.pids, pid) do
      {:ok, set} ->
        new_set = MapSet.delete(set, ref)

        if MapSet.size(new_set) == 0 do
          %{state | pids: Map.delete(state.pids, pid)}
        else
          %{state | pids: Map.put(state.pids, pid, new_set)}
        end

      :error ->
        state
    end
  end

  defp drop_subscription_entry(state, topic, ref) do
    refs = Map.delete(state.refs, ref)

    topics =
      case Map.fetch(state.topics, topic) do
        {:ok, subs} ->
          new_subs = Map.delete(subs, ref)

          if map_size(new_subs) == 0 do
            Map.delete(state.topics, topic)
          else
            Map.put(state.topics, topic, new_subs)
          end

        :error ->
          state.topics
      end

    %{state | topics: topics, refs: refs}
  end

  defp topic_matches?(pattern, topic) do
    p_parts = String.split(pattern, ".")
    t_parts = String.split(topic, ".")

    length(p_parts) == length(t_parts) and
      segments_match?(p_parts, t_parts)
  end

  defp segments_match?([], []), do: true
  defp segments_match?(["*" | pr], [_ | tr]), do: segments_match?(pr, tr)
  defp segments_match?([s | pr], [s | tr]), do: segments_match?(pr, tr)
  defp segments_match?(_, _), do: false
end
```

## New specification

# `FilteredEventBus` — content-based pub/sub GenServer

Implement an Elixir GenServer module `FilteredEventBus`: an in-process pub/sub event system where subscriptions carry **content-based filters** instead of wildcard topic matching. Wildcards are replaced entirely — every subscription uses a literal topic plus an optional filter.

**Rationale (context, not a requirement):**
- Wildcard topic matching routes on a single string field.
- Content-based routing lets subscribers express interest by structural properties — "orders over $1000," "errors from region us-east," "any event where the user is an admin" — which topic wildcards can't express without explosive topic-name proliferation.

**Filter DSL:**
- A **match-spec**-like DSL the bus evaluates on each event, with no `eval` and no anonymous-function storage in state.
- Supports exactly these clauses, combined implicitly as AND:
  - `{:eq, path, value}` — event at `path` equals `value`.
  - `{:neq, path, value}` — event at `path` does not equal `value`.
  - `{:gt, path, value}` / `{:lt, path, value}` / `{:gte, path, value}` / `{:lte, path, value}` — numeric comparison; returns false if either side is non-numeric.
  - `{:in, path, list}` — event value at `path` is a member of `list`.
  - `{:exists, path}` — `path` resolves to a non-nil value.
  - `{:any, [clause, clause, ...]}` — at least one sub-clause matches (OR). Each element is a single clause tuple from this list; a nested clause-*list* (a whole filter) is **not** a valid element.
  - `{:none, [clause, clause, ...]}` — none of the sub-clauses match (NOT-OR, i.e. NAND of the disjunction). Elements are single clause tuples, exactly as for `:any`.

**Paths:**
- A `path` is a list of map keys or integer list indices; each element descends one level.
- A key looks up that key in a map (structs are navigated by key like maps); an integer selects the element at that 0-based index of a list.
- E.g. `[:user, :role]` navigates `event[:user][:role]`; `[:items, 0]` selects the first element of the list at `event[:items]`.
- A path that doesn't resolve returns `nil` (never raises) and fails all clauses except `{:eq, path, nil}` and `{:neq, path, non_nil}`.

**Filter semantics:**
- An entire subscription filter is a list of clauses, ALL of which must match (empty list = always match).
- This differs from `{:any, [...]}`, which is OR within a nested group of clauses.

**Public API:**
- `FilteredEventBus.start_link(opts)` — accepts `:name`.
- `FilteredEventBus.subscribe(server, topic, pid, filter \\ [])` — subscribes `pid` to exact-matching `topic` with the given filter (a list of clauses). Must `Process.monitor` the subscriber. Returns `{:ok, ref}` on success, `{:error, :invalid_filter}` if the filter fails structural validation.
- `FilteredEventBus.unsubscribe(server, topic, ref)` — removes the subscription. Demonitor the pid when its last subscription is removed. Returns `:ok`.
- `FilteredEventBus.publish(server, topic, event)` — sends `{:event, topic, event}` to every subscriber whose topic matches exactly AND whose filter matches the event. Returns `{:ok, matched_count}` — the number of subscribers that received the event.
- `FilteredEventBus.test_filter(filter, event)` — pure utility (no GenServer) returning `true` or `false` for a given filter and event, for subscribers replicating the same filter logic client-side. Returns `{:error, :invalid_filter}` if the filter fails structural validation.

**Filter validation (at subscription time):**
- Recursively check every clause matches one of the shapes above.
- `path`s must be lists of atoms/binaries/integers.
- `:any` / `:none` must contain non-empty lists of valid sub-clauses (bare clause tuples — a nested clause-list element makes the whole filter invalid).
- Validation is structural only — it does NOT evaluate the filter; invalid path types raise no error, they just return `nil` during evaluation.

**Lifecycle & delivery:**
- When a monitored subscriber dies (`:DOWN`), remove all its subscriptions across all topics.
- A single pid may subscribe to the same topic multiple times with different filters and receives one delivery per matching subscription.
- Each subscription has its own ref and is independently unsubscribable.

**Deliverable:**
- Complete module in a single file.
- Use only OTP standard library, no external dependencies.
