# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `stage`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

# Specification — `Pipeline`: Composable Linear Pipelines with Fan-Out Map Stages

## Overview

This document specifies an Elixir module called `Pipeline` that builds and runs linear processing pipelines from composable stages, with support for **fan-out map stages** that process a collection concurrently.

The implementation must use only the standard library, with no external dependencies. The complete implementation is to be delivered in a single file.

## API

The public API consists of the following functions.

### `Pipeline.new()`

Returns a fresh, empty pipeline struct.

### `Pipeline.stage(pipeline, name, fun)`

Appends a normal **sequential** stage. `name` is an atom; `fun` is a one-arity function that receives the current value and returns `{:ok, result}` or `{:error, reason}`.

### `Pipeline.map_stage(pipeline, name, fun, opts \\ [])`

Appends a **fan-out** stage. Its input must be a list. `fun` is a one-arity function applied to **each element** concurrently, returning `{:ok, element_result}` or `{:error, reason}`. `opts` may contain `:max_concurrency` (a positive integer); when omitted, there is no concurrency bound — **every** element runs concurrently at once.

Element results must be collected in **input order**. If every element succeeds, the stage's output is the list of element results (threaded to the next stage). If any element fails, the stage fails with the **first** failure by input index, and the `reason` is that element's `{:error, reason}` reason.

### `Pipeline.run(pipeline, input)`

Executes all stages in insertion order, threading each stage's output into the next.

On full success it returns `{:ok, final_result, metadata}`, where `metadata` is a list of entries in execution order:

- sequential stage: `%{stage: atom, duration_us: non_neg_integer, type: :sequential, count: 1}`
- map stage: `%{stage: atom, duration_us: non_neg_integer, type: :map, count: non_neg_integer}` where `count` is the number of input elements.

On the first failing stage, execution halts immediately and the call returns `{:error, failed_stage_name, reason}` — no later stages are run.

## Implementation constraints

- Fan-out concurrency must use `Task.async_stream/3` (or equivalent) with ordered results and the requested `:max_concurrency`.
- Timing per stage must be measured with `:timer.tc/1` (microsecond resolution).

## Edge cases

- An empty pipeline returns the input unchanged with empty metadata.
- If a map stage receives a non-list input, it raises `ArgumentError`.
- When a map stage has multiple failing elements, the failure reported is the **first** one by input index.
- When `:max_concurrency` is omitted from `opts`, the map stage imposes no concurrency bound and every element runs concurrently at once.

## The module with `stage` missing

```elixir
defmodule Pipeline do
  @moduledoc """
  Composable linear pipelines with concurrent fan-out (`map`) stages.

  Sequential stages thread a single value; a `map_stage/4` applies a function
  to each element of a list concurrently (bounded by `:max_concurrency`),
  collecting results in input order and failing on the first failing element.
  """

  defstruct stages: []

  @type stage_fun :: (any() -> {:ok, any()} | {:error, any()})
  @type t :: %__MODULE__{stages: list()}

  @doc "Returns a fresh, empty pipeline."
  @spec new() :: t()
  def new, do: %__MODULE__{stages: []}

  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    # TODO
  end

  @doc """
  Appends a fan-out map stage. Its input must be a list; `fun` is applied to
  each element concurrently. Option `:max_concurrency` bounds parallelism.
  """
  @spec map_stage(t(), atom(), stage_fun(), keyword()) :: t()
  def map_stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) and is_list(opts) do
    mc = Keyword.get(opts, :max_concurrency, nil)
    %__MODULE__{pipeline | stages: stages ++ [{:map, name, fun, mc}]}
  end

  @doc """
  Runs all stages in order. Returns `{:ok, final, metadata}` or
  `{:error, failed_stage, reason}`.
  """
  @spec run(t(), any()) ::
          {:ok, any(), [map()]} | {:error, atom(), any()}
  def run(%__MODULE__{stages: stages}, input) do
    execute(stages, input, [])
  end

  # ---------------------------------------------------------------------------

  defp execute([], value, meta_acc), do: {:ok, value, Enum.reverse(meta_acc)}

  defp execute([stage | rest], value, meta_acc) do
    case run_stage(stage, value) do
      {:ok, next_value, meta} -> execute(rest, next_value, [meta | meta_acc])
      {:error, name, reason} -> {:error, name, reason}
    end
  end

  defp run_stage({:seq, name, fun}, value) do
    {duration, result} = :timer.tc(fn -> fun.(value) end)

    case result do
      {:ok, next_value} ->
        {:ok, next_value, %{stage: name, duration_us: duration, type: :sequential, count: 1}}

      {:error, reason} ->
        {:error, name, reason}

      other ->
        raise ArgumentError,
              "stage #{inspect(name)} returned an invalid value: #{inspect(other)}."
    end
  end

  defp run_stage({:map, name, fun, mc_opt}, value) do
    unless is_list(value) do
      raise ArgumentError,
            "map stage #{inspect(name)} requires a list input, got: #{inspect(value)}"
    end

    count = length(value)
    max_concurrency = mc_opt || max(count, 1)

    {duration, results} =
      :timer.tc(fn ->
        value
        |> Task.async_stream(fun,
          max_concurrency: max_concurrency,
          ordered: true,
          timeout: :infinity
        )
        |> Enum.map(fn {:ok, element_result} -> element_result end)
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        outputs = Enum.map(results, fn {:ok, v} -> v end)
        {:ok, outputs, %{stage: name, duration_us: duration, type: :map, count: count}}

      {:error, reason} ->
        {:error, name, reason}
    end
  end
end
```

Output only `stage` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
