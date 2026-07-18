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
defmodule Workflow do
  @states [
    :draft,
    :submitted,
    :approved,
    :in_progress,
    :completed,
    :rejected,
    :cancelled
  ]

  # event => {from, to}
  @transitions %{
    submit: {:draft, :submitted},
    approve: {:submitted, :approved},
    reject: {:submitted, :rejected},
    start: {:approved, :in_progress},
    complete: {:in_progress, :completed},
    cancel: {:in_progress, :cancelled}
  }

  def new(attrs \\ %{}) when is_map(attrs) do
    attrs
    |> Map.put(:state, :draft)
    |> Map.put(:history, [])
  end

  def states, do: @states

  def transition(%{state: current, history: history} = record, event) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record) do
          updated =
            record
            |> Map.put(:state, to)
            |> Map.put(:history, [{event, current, to} | history])

          {:ok, updated}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  def undo(%{history: []}), do: {:error, :nothing_to_undo}

  def undo(%{history: [{_event, from, _to} | rest]} = record) do
    {:ok, record |> Map.put(:state, from) |> Map.put(:history, rest)}
  end

  def can?(record, event) do
    match?({:ok, _}, transition(record, event))
  end

  def history(%{history: history}) do
    history
    |> Enum.reverse()
    |> Enum.map(fn {event, _from, _to} -> event end)
  end

  # Guards: true when permitted.
  defp guard(:submit, %{items: items}) when is_list(items) and items != [], do: true
  defp guard(:submit, _record), do: false

  defp guard(:approve, %{approved_by: approved_by})
       when is_binary(approved_by) and approved_by != "",
       do: true

  defp guard(:approve, _record), do: false

  defp guard(_event, _record), do: true
end
```
