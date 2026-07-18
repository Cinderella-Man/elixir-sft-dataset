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
    Map.put(attrs, :state, :draft)
  end

  def states, do: @states

  def transition(record, event, payload \\ %{})

  def transition(%{state: current} = record, event, payload) when is_map(payload) do
    case Map.fetch(@transitions, event) do
      {:ok, {^current, to}} ->
        if guard(event, record, payload) do
          updated =
            record
            |> Map.put(:state, to)
            |> effect(event, payload)

          {:ok, updated}
        else
          {:error, :guard_failed, current, event}
        end

      _ ->
        {:error, :invalid_transition, current, event}
    end
  end

  def can?(record, event, payload \\ %{}) do
    match?({:ok, _}, transition(record, event, payload))
  end

  # Guards: return true when the transition is permitted.

  defp guard(:submit, %{items: items}, _payload) when is_list(items) and items != [], do: true
  defp guard(:submit, _record, _payload), do: false

  defp guard(:approve, _record, %{approver: a}) when is_binary(a) and a != "", do: true
  defp guard(:approve, _record, _payload), do: false

  defp guard(:reject, _record, %{reason: r}) when is_binary(r) and r != "", do: true
  defp guard(:reject, _record, _payload), do: false

  defp guard(_event, _record, _payload), do: true

  # Effects: applied after the state change on success.

  defp effect(record, :approve, %{approver: a}), do: Map.put(record, :approved_by, a)

  defp effect(record, :reject, %{reason: r}), do: Map.put(record, :rejection_reason, r)

  defp effect(record, :complete, _payload), do: Map.put(record, :completed, true)

  defp effect(record, :cancel, %{reason: r}) when is_binary(r),
    do: Map.put(record, :cancelled_reason, r)

  defp effect(record, _event, _payload), do: record
end
```
