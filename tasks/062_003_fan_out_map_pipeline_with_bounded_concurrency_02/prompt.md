Implement the private `run_stage/2` function. It comes in two clauses, one per
stage type, and each returns either `{:ok, output, metadata}` or
`{:error, stage_name, reason}`.

**Sequential clause** — for a `{:seq, name, fun}` stage:
- Invoke `fun.(value)`, measuring wall-clock time with `:timer.tc/1` (microsecond
  resolution) so you capture both the duration and the function's result.
- If the function returns `{:ok, next_value}`, succeed with `next_value` and the
  metadata map `%{stage: name, duration_us: duration, type: :sequential, count: 1}`.
- If it returns `{:error, reason}`, fail with `{:error, name, reason}`.
- For any other return value, raise `ArgumentError` explaining that the stage
  returned an invalid value (include the stage name and the offending value).

**Map (fan-out) clause** — for a `{:map, name, fun, mc_opt}` stage:
- The input `value` must be a list; if it is not, raise `ArgumentError` naming the
  stage and showing the received input.
- Let `count` be the number of elements. Determine the effective concurrency: use
  `mc_opt` when provided, otherwise allow all elements to run concurrently
  (`max(count, 1)`).
- Apply `fun` to each element concurrently using `Task.async_stream/3` with
  `ordered: true`, the chosen `max_concurrency`, and `timeout: :infinity`, so
  element results are collected in input order. Unwrap each `{:ok, element_result}`
  tuple produced by the stream to get the raw `{:ok, v}` / `{:error, reason}` value
  returned by `fun`. Wrap the whole collection in `:timer.tc/1` to measure duration.
- If no element result matches `{:error, _}`, the stage succeeds: unwrap each
  `{:ok, v}` into the list of outputs and return it with metadata
  `%{stage: name, duration_us: duration, type: :map, count: count}`.
- Otherwise fail with `{:error, name, reason}` using the **first** failing element's
  reason (by input index).

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

  @doc "Appends a sequential stage."
  @spec stage(t(), atom(), stage_fun()) :: t()
  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{:seq, name, fun}]}
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
    # TODO
  end
end
```