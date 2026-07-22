Implement the public `resume/3` function. It resumes a saga run from a previously
produced journal instead of starting from scratch.

Given the saga's step list, an incoming `context` map, and a chronological
`journal`, `resume/3` must:

1. Collect the names of every step that already completed by scanning the journal
   for `{:completed, name, _result}` events.
2. Rebuild the accumulated context by folding over the journal and merging each
   `{:completed, name, result}` under `name` (ignoring all other event kinds).
   The already-completed actions are **not** re-invoked.
3. Split the saga's steps into the already-`done` steps (whose names appear in the
   completed set — assume these form a prefix) and the `remaining` steps still to
   run.
4. Seed a reverse-order journal accumulator with just the `{:completed, _, _}`
   events from the incoming journal (filtered, then reversed) so that the final
   returned journal stays chronological once it is reversed at the end.
5. Delegate to the private `run/4` helper with the `remaining` steps, the `done`
   steps in reverse-execution order (`Enum.reverse(done_steps)`) as the
   already-completed accumulator, the rebuilt context, and the seeded reverse
   journal.

The function head should pattern-match the saga struct's `steps` and guard that
`context` is a map and `journal` is a list. An empty journal must make `resume/3`
behave exactly like `execute/2`.

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with a **durable journal** and **crash-resumable execution**.

  Each run emits a chronological list of events — `{:completed, name, result}`,
  `{:failed, name, reason}`, `{:compensated, name, value}` — returned alongside
  the usual result. `resume/3` rebuilds state from such a journal, skipping the
  actions of steps that already completed and continuing with the rest. A
  failure during a resumed run rolls back every completed step (replayed and
  newly run alike) in reverse order.
  """

  @typedoc "An accumulated context passed to every action and compensation."
  @type context :: map()

  @typedoc "The result an action function must return."
  @type action_result :: {:ok, term()} | {:error, term()}

  @typedoc "A single named step in the saga definition."
  @type step_entry :: %{
          name: atom(),
          action: (context() -> action_result()),
          compensate: (context() -> term())
        }

  @typedoc "A single chronological journal event."
  @type event ::
          {:completed, atom(), term()}
          | {:failed, atom(), term()}
          | {:compensated, atom(), term()}

  @typedoc "An ordered, chronological list of journal events."
  @type journal :: [event()]

  @typedoc "The saga struct holding an ordered list of steps."
  @type t :: %__MODULE__{steps: [step_entry()]}

  @typedoc "The value returned by `execute/2` and `resume/3`."
  @type run_result ::
          {:ok, context(), journal()}
          | {:error, atom(), term(), keyword(), journal()}

  defstruct steps: []

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Appends a named step."
  @spec step(t(), atom(), (context() -> action_result()), (context() -> term())) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga from the beginning."
  @spec execute(t(), context()) :: run_result()
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context, [])
  end

  @doc "Resumes execution from a previously produced journal."
  @spec resume(t(), context(), journal()) :: run_result()
  def resume(%__MODULE__{steps: steps}, context, journal)
      when is_map(context) and is_list(journal) do
    # TODO
  end

  # --- execution -----------------------------------------------------------
  #
  # `completed` is in reverse-execution order (most recent first).
  # `jrev` is the journal accumulated in reverse (most recent event first).

  @spec run([step_entry()], [step_entry()], context(), journal()) :: run_result()
  defp run([], _completed, context, jrev), do: {:ok, context, Enum.reverse(jrev)}

  defp run([%{name: name, action: action} = step | rest], completed, context, jrev) do
    case safe(action, context) do
      {:ok, result} ->
        run(
          rest,
          [step | completed],
          Map.put(context, name, result),
          [{:completed, name, result} | jrev]
        )

      {:error, reason} ->
        {comp, jrev2} = compensate_all(completed, context, [{:failed, name, reason} | jrev])
        {:error, name, reason, comp, Enum.reverse(jrev2)}
    end
  end

  @spec safe((context() -> term()), context()) :: action_result()
  defp safe(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end

  # --- compensation --------------------------------------------------------

  @spec compensate_all([step_entry()], context(), journal()) :: {keyword(), journal()}
  defp compensate_all(completed, context, jrev0) do
    Enum.reduce(completed, {[], jrev0}, fn %{name: name, compensate: compensate}, {acc, jrev} ->
      value = safe_compensate(compensate, context)
      {acc ++ [{name, value}], [{:compensated, name, value} | jrev]}
    end)
  end

  @spec safe_compensate((context() -> term()), context()) :: term()
  defp safe_compensate(compensate, context) do
    compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  catch
    kind, value -> {:caught, kind, value}
  end
end
```