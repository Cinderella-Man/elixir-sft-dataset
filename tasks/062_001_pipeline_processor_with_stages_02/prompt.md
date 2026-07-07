Implement the private `execute/3` function. It is the recursive engine behind
`Pipeline.run/2`: it walks the list of stages in order, threading each stage's
result into the next, while accumulating timing metadata.

`execute/3` takes three arguments: the remaining list of `{name, fun}` stage
tuples, the current `value` being threaded through the pipeline, and
`meta_acc`, a list of `%{stage: atom, duration_us: non_neg_integer}` maps
accumulated so far in **reverse** execution order (most recent first).

Write it as two clauses:

- **Base case** — when the stage list is empty, every stage has succeeded.
  Return `{:ok, value, metadata}` where `metadata` is `meta_acc` reversed back
  into execution order.

- **Recursive case** — when at least one stage `{name, fun}` remains, run that
  stage's `fun` on the current `value`, measuring its wall-clock duration in
  microseconds with `:timer.tc/1`. Build a metadata entry
  `%{stage: name, duration_us: duration_us}` for the stage that just ran. Then
  inspect the stage's result:
  - `{:ok, next_value}` — recurse into the remaining stages with `next_value`
    as the new value, prepending this stage's metadata entry to `meta_acc`.
  - `{:error, reason}` — halt immediately and return `{:error, name, reason}`,
    running none of the subsequent stages.
  - anything else — raise an `ArgumentError` explaining that the stage returned
    an invalid value and that `{:ok, result}` or `{:error, reason}` was
    expected.

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

  defp execute([], value, meta_acc) do
    # TODO
  end
end

```