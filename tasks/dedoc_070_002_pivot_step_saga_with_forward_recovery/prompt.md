# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Saga do
  defstruct steps: []

  def new, do: %__MODULE__{}

  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{kind: :compensable, name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  def retriable(%__MODULE__{} = saga, name, action_fn, max_attempts)
      when is_atom(name) and is_function(action_fn, 1) and is_integer(max_attempts) and
             max_attempts >= 1 do
    entry = %{kind: :retriable, name: name, action: action_fn, max_attempts: max_attempts}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context)
  end

  # --- execution -----------------------------------------------------------

  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :compensable, name: name, action: action} = step | rest],
         completed,
         context
       ) do
    case safe(action, context) do
      {:ok, result} ->
        run(rest, [step | completed], Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, reason, compensate_all(completed, context)}
    end
  end

  defp run(
         [%{kind: :retriable, name: name, action: action, max_attempts: max} | rest],
         completed,
         context
       ) do
    case attempt(action, context, max, 1) do
      {:ok, result} ->
        run(rest, completed, Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, {:retries_exhausted, reason}, []}
    end
  end

  defp attempt(action, context, max, n) do
    case safe(action, context) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        if n >= max, do: {:error, reason}, else: attempt(action, context, max, n + 1)
    end
  end

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

  defp compensate_all(completed, context) do
    Enum.map(completed, fn %{name: name, compensate: compensate} ->
      {name, safe_compensate(compensate, context)}
    end)
  end

  defp safe_compensate(compensate, context) do
    compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  catch
    kind, value -> {:caught, kind, value}
  end
end
```
