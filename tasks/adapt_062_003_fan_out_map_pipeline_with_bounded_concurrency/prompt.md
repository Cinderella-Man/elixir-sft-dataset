# Rework this solution for a changed brief

The module below is a complete, tested solution to a neighboring task. Treat
it as your starting codebase, not as a suggestion — carry over what still
fits and rewrite what the new brief demands. Where old code and the new
specification conflict (module name, public API, behavior, constraints,
output format), the new specification is authoritative. Return the complete
final result.

## Existing code (your starting point)

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
      {:ok, next_value} ->
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

## New specification

Write me an Elixir module called `Pipeline` that builds and runs linear processing pipelines from composable stages, with support for **fan-out map stages** that process a collection concurrently.

I need these functions in the public API:
- `Pipeline.new()` — returns a fresh, empty pipeline struct.
- `Pipeline.stage(pipeline, name, fun)` — appends a normal **sequential** stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`.
- `Pipeline.map_stage(pipeline, name, fun, opts \\ [])` — appends a **fan-out** stage. Its input must be a list. `fun` is a one-arity function applied to **each element** concurrently, returning `{:ok, element_result}` or `{:error, reason}`. `opts` may contain `:max_concurrency` (a positive integer); when omitted, there is no concurrency bound — **every** element runs concurrently at once. Element results must be collected in **input order**. If every element succeeds, the stage's output is the list of element results (threaded to the next stage). If any element fails, the stage fails with the **first** failure by input index, and the `reason` is that element's `{:error, reason}` reason.
- `Pipeline.run(pipeline, input)` — executes all stages in insertion order, threading each stage's output into the next. An empty pipeline returns the input unchanged with empty metadata. On full success return `{:ok, final_result, metadata}` where `metadata` is a list of entries in execution order:
  - sequential stage: `%{stage: atom, duration_us: non_neg_integer, type: :sequential, count: 1}`
  - map stage: `%{stage: atom, duration_us: non_neg_integer, type: :map, count: non_neg_integer}` where `count` is the number of input elements.
  On the first failing stage, immediately halt and return `{:error, failed_stage_name, reason}` — do not run any later stages.

Fan-out concurrency must use `Task.async_stream/3` (or equivalent) with ordered results and the requested `:max_concurrency`. Timing per stage must be measured with `:timer.tc/1` (microsecond resolution). If a map stage receives a non-list input, raise `ArgumentError`.

Use only the standard library, no external dependencies. Give me the complete implementation in a single file.
