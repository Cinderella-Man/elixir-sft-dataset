# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines from composable stages.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a named stage to the pipeline and returns a new pipeline, leaving the original unchanged so a base pipeline can be branched and reused. `name` is an atom, `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. Guard the arguments so that a non-atom `name` or a function of the wrong arity raises `FunctionClauseError`. Stages must be stored in insertion order (duplicate names are allowed and each occurrence runs).
- `Pipeline.run(pipeline, input)` — executes all stages in order, threading the result of each stage as the input to the next. If every stage succeeds, return `{:ok, final_result, metadata}` where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer}` entries in execution order. A pipeline with no stages returns `{:ok, input, []}`. If any stage returns `{:error, reason}`, immediately halt and return `{:error, failed_stage_name, reason}` — do not execute any subsequent stages, and return `reason` verbatim regardless of its shape.

Timing per stage must be measured with `:timer.tc/1` (or equivalent microsecond-resolution call); each metadata entry's `duration_us` is a non-negative integer. Metadata is returned only in the success tuple — the `{:error, failed_stage_name, reason}` halt result carries no metadata list.

The module must be pure — no processes, no GenServer, no global state. It should be a plain Elixir module whose stages run entirely in the caller's process, so repeated runs of the same pipeline are independent.

Give me the complete implementation in a single file. Use only the standard library, no external dependencies.

## The buggy module

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear processing pipelines.

  Stages are executed in insertion order, each receiving the previous stage's
  result as input. Timing metadata (in microseconds) is collected for every
  stage that actually runs.

  ## Example

      iex> Pipeline.new()
      ...> |> Pipeline.stage(:parse,    fn s -> {:ok, String.to_integer(s)} end)
      ...> |> Pipeline.stage(:double,   fn n -> {:ok, n * 2} end)
      ...> |> Pipeline.stage(:to_str,   fn n -> {:ok, Integer.to_string(n)} end)
      ...> |> Pipeline.run("21")
      {:ok, "42", [
        %{stage: :parse,   duration_us: ...},
        %{stage: :double,  duration_us: ...},
        %{stage: :to_str,  duration_us: ...}
      ]}
  """

  @enforce_keys [:stages]
  defstruct stages: []

  @type stage_meta :: %{stage: atom(), duration_us: non_neg_integer()}

  @type t :: %__MODULE__{
          stages: [{atom(), (any() -> {:ok, any()} | {:error, any()})}]
        }

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  @doc """
  Appends a named stage to the pipeline.

  `fun` must be a one-arity function that returns either
  `{:ok, result}` or `{:error, reason}`.
  """
  @spec stage(t(), atom(), (any() -> {:ok, any()} | {:error, any()})) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{name, fun}]}
  end

  @doc """
  Executes all stages in insertion order, threading results through the chain.

  Returns:
  - `{:ok, final_result, [%{stage: atom, duration_us: non_neg_integer}]}` — all stages passed.
  - `{:error, failed_stage, reason}` — a stage failed; subsequent stages are skipped.

  Timing is recorded (via `:timer.tc/1`) for every stage that actually ran,
  including the one that failed.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [stage_meta()]}
          | {:error, atom(), any()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  # Base case — all stages completed successfully.
  defp execute([], value, meta_acc) do
    {:ok, value, Enum.reverse(meta_acc)}
  end

  defp execute([{name, fun} | rest], value, meta_acc) do
    {duration_us, result} = :timer.tc(fn -> fun.(value) end)
    meta = %{stage: name, duration_us: duration_us}

    case result do
      {:error, next_value} ->
        execute(rest, next_value, [meta | meta_acc])

      {:error, reason} ->
        # Return accumulated metadata (in execution order) as part of caller
        # context — exposed via the three-element error tuple if desired, but
        # the public contract only requires the three-element form below.
        # We honour the spec strictly here.
        {:error, name, reason}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}. " <>
                "Expected {:ok, result} or {:error, reason}."
    end
  end
end
```

## Failing test report

```
12 of 15 test(s) failed:

  * test single stage runs and returns ok with metadata
      stage :double returned an invalid value: {:ok, 84}. Expected {:ok, result} or {:error, reason}.

  * test three stages thread results correctly
      stage :add_one returned an invalid value: {:ok, 5}. Expected {:ok, result} or {:error, reason}.

  * test stages receive exactly the previous stage's output
      stage :one returned an invalid value: {:ok, 10}. Expected {:ok, result} or {:error, reason}.

  * test first stage failing returns error with correct stage name and reason
      stage :transform returned an invalid value: {:ok, :timeout}. Expected {:ok, result} or {:error, reason}.

  (…8 more)
```
