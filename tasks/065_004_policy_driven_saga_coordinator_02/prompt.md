# Fill in the Middle: `do_compensate/4`

Implement the private `do_compensate/4` function, the recursive heart of the
compensation pass. It walks the list of completed steps (given in **reverse
completion order**, most recently completed first) and runs each step's
`compensation` on the accumulated `context`, honoring each step's rollback policy.

It is called as `do_compensate(completed, context, ran, results)` and must return the
4-tuple `{ran, results, aborted_at, uncompensated}` where:

- `ran` is the list of step names whose compensations were attempted, in **reverse
  run order** (most recent first) — the caller reverses it.
- `results` is a map `name => compensation_return_value` for every attempted
  compensation.
- `aborted_at` is the name of the compensation whose `{:error, _}` under an `:abort`
  policy stopped the pass, or `nil` if the whole list was processed normally.
- `uncompensated` is the list of the *remaining* completed step names that were not
  run because the pass aborted, in the order they would have run (`[]` if the pass
  completed normally).

Behavior:

- **Empty list:** nothing left to compensate — return `{ran, results, nil, []}`.
- **Non-empty list:** run the head step's `compensation` on `context`, prepend its
  `name` to `ran`, and record its return value in `results` under `name`. Then:
  - If the compensation returned `{:error, _}` **and** the step's `policy` is
    `:abort`, stop immediately: return the updated `ran` and `results`, set
    `aborted_at` to this step's `name`, and set `uncompensated` to the names of the
    remaining (not-yet-run) steps in order.
  - Otherwise (success, or `{:error, _}` under `:continue`), recurse on the rest of
    the list, threading the updated `ran` and `results`.

```elixir
defmodule PolicySaga do
  @moduledoc """
  A saga / compensating-transaction coordinator with a per-step **rollback policy**.

  Steps run in order; on a step failure the compensations of previously-completed
  steps run in reverse completion order. A step's `:on_error` policy governs what
  happens if *its own compensation* returns `{:error, _}`:

    * `:continue` (default) — record and keep rolling back (best-effort).
    * `:abort` — stop the rollback immediately; earlier steps are left uncompensated.
  """

  @opaque t :: %__MODULE__{steps: [step()]}
  @type context :: map()
  @type policy :: :continue | :abort
  @type step :: %{
          name: term(),
          action: (context() -> {:ok, term()} | {:error, term()}),
          compensation: (context() -> term()),
          policy: policy()
        }
  @type error :: %{
          step: term(),
          error: term(),
          compensated: [term()],
          compensations: %{optional(term()) => term()},
          aborted_at: term() | nil,
          uncompensated: [term()]
        }

  defstruct steps: []

  @doc "Returns a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{steps: []}

  @doc """
  Appends a step. `opts` supports `:on_error` (`:continue` default, or `:abort`).
  """
  @spec step(
          t(),
          term(),
          (context() -> {:ok, term()} | {:error, term()}),
          (context() -> term()),
          keyword()
        ) :: t()
  def step(%__MODULE__{steps: steps} = saga, name, action, compensation, opts \\ [])
      when is_function(action, 1) and is_function(compensation, 1) do
    policy = Keyword.get(opts, :on_error, :continue)

    unless policy in [:continue, :abort] do
      raise ArgumentError, "on_error must be :continue or :abort, got: #{inspect(policy)}"
    end

    step = %{name: name, action: action, compensation: compensation, policy: policy}
    %__MODULE__{saga | steps: steps ++ [step]}
  end

  @doc "Runs the saga from `context`."
  @spec execute(t(), context()) :: {:ok, context()} | {:error, error()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    forward(steps, context, [])
  end

  # `completed` is in reverse completion order (most recent first).
  defp forward([], context, _completed), do: {:ok, context}

  defp forward([step | rest], context, completed) do
    case step.action.(context) do
      {:ok, result} ->
        forward(rest, Map.put(context, step.name, result), [step | completed])

      {:error, reason} ->
        compensate(completed, context, step.name, reason)
    end
  end

  defp compensate(completed, context, failed_step, reason) do
    {ran, compensations, aborted_at, uncompensated} =
      do_compensate(completed, context, [], %{})

    {:error,
     %{
       step: failed_step,
       error: reason,
       compensated: Enum.reverse(ran),
       compensations: compensations,
       aborted_at: aborted_at,
       uncompensated: uncompensated
     }}
  end

  # Returns {ran (reverse run order), compensations, aborted_at, uncompensated}.
  defp do_compensate(completed, context, ran, results) do
    # TODO
  end
end
```