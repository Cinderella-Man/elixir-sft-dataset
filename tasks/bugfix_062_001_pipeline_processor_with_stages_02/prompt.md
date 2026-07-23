# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

I need you to write me an Elixir module called `Pipeline` that lets callers build and run linear processing pipelines out of composable stages. Here's what I need from the public API.

`Pipeline.new()` should hand back a fresh, empty pipeline struct.

`Pipeline.stage(pipeline, name, fun)` appends a named stage to the pipeline and returns a new pipeline — the original has to stay untouched, because I want to be able to branch and reuse a base pipeline. `name` is an atom, and `fun` is a one-arity function that receives the current value and returns either `{:ok, result}` or `{:error, reason}`. Please guard the arguments so that a non-atom `name` or a function of the wrong arity raises `FunctionClauseError`. Stages need to be stored in insertion order, and duplicate names are fine — each occurrence should run.

`Pipeline.run(pipeline, input)` executes all stages in order, threading the result of each stage in as the input to the next. When every stage succeeds, I want back `{:ok, final_result, metadata}`, where `metadata` is a list of `%{stage: atom, duration_us: non_neg_integer}` entries in execution order. A pipeline with no stages returns `{:ok, input, []}`. If any stage returns `{:error, reason}`, halt right there and return `{:error, failed_stage_name, reason}` — don't execute any of the subsequent stages, and pass `reason` back verbatim no matter what shape it has.

Time each stage with `:timer.tc/1` (or an equivalent microsecond-resolution call); each metadata entry's `duration_us` is a non-negative integer. Metadata only shows up in the success tuple — the `{:error, failed_stage_name, reason}` halt result carries no metadata list.

Keep the module pure: no processes, no GenServer, no global state. It should be a plain Elixir module whose stages run entirely in the caller's process, so repeated runs of the same pipeline are independent of each other.

Send me the complete implementation in a single file, standard library only, no external dependencies.

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
      when is_atom(name) and is_function(fun, 2) do
    %__MODULE__{pipeline | stages: stages ++ [{name, fun}]}
  end

  @doc """
  Executes all stages in insertion order, threading results through the chain.

  Returns:
  - `{:ok, final_result, [%{stage: atom, duration_us: non_neg_integer}]}` — all stages passed.
  - `{:error, failed_stage, reason}` — a stage failed; subsequent stages are skipped.

  Timing is measured with `:timer.tc/1` around every stage invocation, but
  metadata travels only in the success tuple — the error result carries no
  metadata list, so a failed run discards the timings collected so far.
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
      {:ok, next_value} ->
        execute(rest, next_value, [meta | meta_acc])

      {:error, reason} ->
        # The contract's halt result is exactly three elements with no
        # metadata list — the timings accumulated so far are dropped.
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
19 of 21 test(s) failed:

  * test stage/3 returns a Pipeline struct
      no function clause matching in Pipeline.stage/3

  * test single stage runs and returns ok with metadata
      no function clause matching in Pipeline.stage/3

  * test three stages thread results correctly
      no function clause matching in Pipeline.stage/3

  * test stages receive exactly the previous stage's output
      no function clause matching in Pipeline.stage/3

  (…15 more)
```
