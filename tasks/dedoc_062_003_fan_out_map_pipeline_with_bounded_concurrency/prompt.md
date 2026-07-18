# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule Pipeline do
  defstruct stages: []

  def new, do: %__MODULE__{stages: []}

  def stage(%__MODULE__{stages: stages} = pipeline, name, fun)
      when is_atom(name) and is_function(fun, 1) do
    %__MODULE__{pipeline | stages: stages ++ [{:seq, name, fun}]}
  end

  def map_stage(%__MODULE__{stages: stages} = pipeline, name, fun, opts \\ [])
      when is_atom(name) and is_function(fun, 1) and is_list(opts) do
    mc = Keyword.get(opts, :max_concurrency, nil)
    %__MODULE__{pipeline | stages: stages ++ [{:map, name, fun, mc}]}
  end

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
