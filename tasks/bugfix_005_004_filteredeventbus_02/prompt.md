# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

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

## The buggy module

```elixir
defmodule FilteredEventBus do
  @moduledoc """
  An in-process pub/sub bus with content-based filter subscriptions.

  Replaces wildcard topic matching with a small, evaluable match-spec DSL
  stored per subscription.  Each subscription carries a list of clauses
  (implicit AND); an event is delivered only when every clause matches.

  Supported clauses:

      {:eq, path, value}                   – event[path] == value
      {:neq, path, value}                  – event[path] != value
      {:gt | :lt | :gte | :lte, path, v}   – numeric comparisons
      {:in, path, list}                    – event[path] ∈ list
      {:exists, path}                      – event[path] is not nil
      {:any, [clause, ...]}                – at least one sub-clause matches
      {:none, [clause, ...]}               – no sub-clause matches

  `path` is a list of map keys or integer list indices.  A path that fails to
  resolve yields `nil` (never raises); most clauses fail against `nil`.

  State:

      %{
        topics: %{topic => [%{ref, pid, filter}, ...]},
        monitors: %{ref => {pid, [topic, ...]}}
      }

  ## Options

    * `:name` – optional process registration

  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec subscribe(GenServer.server(), String.t(), pid(), list()) ::
          {:ok, reference()} | {:error, :invalid_filter}
  def subscribe(server, topic, pid, filter \\ [])
      when is_binary(topic) and is_pid(pid) and is_list(filter) do
    if valid_filter?(filter) do
      GenServer.call(server, {:subscribe, topic, pid, filter})
    else
      {:error, :invalid_filter}
    end
  end

  @spec unsubscribe(GenServer.server(), String.t(), reference()) :: :ok
  def unsubscribe(server, topic, ref), do: GenServer.call(server, {:unsubscribe, topic, ref})

  @spec publish(GenServer.server(), String.t(), term()) :: {:ok, non_neg_integer()}
  def publish(server, topic, event) when is_binary(topic) do
    GenServer.call(server, {:publish, topic, event})
  end

  @doc """
  Pure evaluation of `filter` against `event`, outside any GenServer.
  Returns `true | false`, or `{:error, :invalid_filter}` if the filter fails
  structural validation.
  """
  @spec test_filter(list(), term()) :: boolean() | {:error, :invalid_filter}
  def test_filter(filter, event) when is_list(filter) do
    if valid_filter?(filter) do
      eval_filter(filter, event)
    else
      {:error, :invalid_filter}
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{topics: %{}, monitors: %{}}}
  end

  @impl true
  def handle_call({:subscribe, topic, pid, filter}, _from, state) do
    ref = Process.monitor(pid)
    sub = %{ref: ref, pid: pid, filter: filter}

    subs_for_topic = Map.get(state.topics, topic, []) ++ [sub]

    monitors =
      Map.update(state.monitors, ref, {pid, [topic]}, fn {p, topics} ->
        {p, Enum.uniq([topic | topics])}
      end)

    {:reply, {:ok, ref},
     %{state | topics: Map.put(state.topics, topic, subs_for_topic), monitors: monitors}}
  end

  def handle_call({:unsubscribe, topic, ref}, _from, state) do
    {:reply, :ok, remove_ref_from_topic(state, topic, ref)}
  end

  def handle_call({:publish, topic, event}, _from, state) do
    subs = Map.get(state.topics, topic, [])

    matched =
      Enum.reduce(subs, 0, fn sub, acc ->
        if eval_filter(sub.filter, event) do
          send(sub.pid, {:event, topic, event})
          acc + 1
        else
          acc
        end
      end)

    {:reply, {:ok, matched}, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.monitors, ref) do
      {nil, _} ->
        {:noreply, state}

      {{_pid, topics}, monitors} ->
        new_topics =
          Enum.reduce(topics, state.topics, fn topic, acc ->
            case Map.get(acc, topic) do
              nil -> acc
              subs -> Map.put(acc, topic, Enum.reject(subs, &(&1.ref == ref)))
            end
          end)

        {:noreply, %{state | topics: new_topics, monitors: monitors}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Filter validation
  # ---------------------------------------------------------------------------

  defp valid_filter?(filter) when is_list(filter) do
    Enum.all?(filter, &valid_clause?/1)
  end

  defp valid_clause?({op, path, _val})
       when op in [:eq, :neq, :gt, :lt, :gte, :lte] and is_list(path) do
    valid_path?(path)
  end

  defp valid_clause?({:in, path, list}) when is_list(path) and is_list(list) do
    valid_path?(path)
  end

  defp valid_clause?({:exists, path}) when is_list(path), do: valid_path?(path)

  defp valid_clause?({:any, subs}) when is_list(subs) and subs != [] do
    Enum.all?(subs, &valid_clause?/1)
  end

  defp valid_clause?({:none, subs}) when is_list(subs) and subs != [] do
    Enum.all?(subs, &valid_clause?/1)
  end

  defp valid_clause?(_), do: true

  defp valid_path?(path) do
    Enum.all?(path, fn
      k when is_atom(k) or is_binary(k) or is_integer(k) -> true
      _ -> false
    end)
  end

  # ---------------------------------------------------------------------------
  # Filter evaluation
  # ---------------------------------------------------------------------------

  # Top-level filter: list of clauses, all must match.
  defp eval_filter(filter, event) do
    Enum.all?(filter, &eval_clause(&1, event))
  end

  defp eval_clause({:eq, path, value}, event), do: fetch(event, path) == value
  defp eval_clause({:neq, path, value}, event), do: fetch(event, path) != value

  defp eval_clause({:gt, path, value}, event), do: num_cmp(fetch(event, path), value, &>/2)
  defp eval_clause({:lt, path, value}, event), do: num_cmp(fetch(event, path), value, &</2)
  defp eval_clause({:gte, path, value}, event), do: num_cmp(fetch(event, path), value, &>=/2)
  defp eval_clause({:lte, path, value}, event), do: num_cmp(fetch(event, path), value, &<=/2)

  defp eval_clause({:in, path, list}, event), do: fetch(event, path) in list

  defp eval_clause({:exists, path}, event), do: fetch(event, path) != nil

  defp eval_clause({:any, subs}, event), do: Enum.any?(subs, &eval_clause(&1, event))

  defp eval_clause({:none, subs}, event), do: not Enum.any?(subs, &eval_clause(&1, event))

  # Numeric comparison that returns false for non-numeric operands (including nil).
  defp num_cmp(a, b, op) when is_number(a) and is_number(b), do: op.(a, b)
  defp num_cmp(_, _, _), do: false

  # Path navigation: maps by key, lists by integer index.  Missing keys → nil.
  defp fetch(value, []), do: value

  defp fetch(map, [key | rest]) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, v} -> fetch(v, rest)
      :error -> nil
    end
  end

  defp fetch(list, [idx | rest]) when is_list(list) and is_integer(idx) do
    case Enum.at(list, idx, :__missing__) do
      :__missing__ -> nil
      v -> fetch(v, rest)
    end
  end

  defp fetch(_, _), do: nil

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp remove_ref_from_topic(state, topic, ref) do
    case Map.get(state.topics, topic) do
      nil ->
        state

      subs ->
        new_subs = Enum.reject(subs, &(&1.ref == ref))
        topics = Map.put(state.topics, topic, new_subs)

        monitors =
          case Map.fetch(state.monitors, ref) do
            {:ok, {pid, topics_list}} ->
              remaining = List.delete(topics_list, topic)

              if remaining == [] do
                Process.demonitor(ref, [:flush])
                Map.delete(state.monitors, ref)
              else
                Map.put(state.monitors, ref, {pid, remaining})
              end

            :error ->
              state.monitors
          end

        %{state | topics: topics, monitors: monitors}
    end
  end
end
```

## Failing test report

```
2 of 20 test(s) failed:

  * test invalid filters are rejected at subscribe
      
      
      match (=) failed
      code:  assert {:error, :invalid_filter} = FilteredEventBus.subscribe(bus, "t", self(), [{:unknown_op, [:a], 1}])
      left:  {:error, :invalid_filter}
      right: {:ok, #Reference<0.2186830597.905707522.8966>}
      

  * test test_filter returns booleans without a running bus
      no function clause matching in FilteredEventBus.eval_clause/2
```
