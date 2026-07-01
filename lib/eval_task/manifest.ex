defmodule EvalTask.Manifest do
  @moduledoc """
  Per-task configuration for multi-file tasks. Values are inferred from the
  harness by default; an optional `manifest.exs` in the task dir overrides them.

  Fields: `:archetype` (`:phoenix_conncase | :plug_selfcontained | :pure_otp`),
  `:prefix`, `:web_prefix`, `:otp_app`, `:db` (`:sqlite | :postgres | :fake | :none`),
  `:migrations`, `:async`.
  """

  @type t :: %{
          archetype: :phoenix_conncase | :plug_selfcontained | :pure_otp,
          prefix: String.t() | nil,
          web_prefix: String.t() | nil,
          otp_app: atom() | nil,
          db: :sqlite | :postgres | :fake | :none
        }

  @doc "Resolve config for `task_dir`, inferring from `harness_src`, overridden by manifest.exs."
  @spec resolve(String.t(), String.t()) :: t()
  def resolve(task_dir, harness_src) do
    inferred = infer(harness_src)

    case load_manifest(task_dir) do
      nil -> inferred
      overrides -> Map.merge(inferred, overrides)
    end
  end

  @doc "Infer config from the harness source alone."
  @spec infer(String.t()) :: t()
  def infer(harness_src) do
    cond do
      match = Regex.run(~r/use\s+(\w+)\.ConnCase/, harness_src) ->
        [_, web] = match
        prefix = String.replace_suffix(web, "Web", "")

        %{
          archetype: :phoenix_conncase,
          prefix: prefix,
          web_prefix: web,
          otp_app: prefix |> Macro.underscore() |> String.to_atom(),
          db: :sqlite
        }

      harness_src =~ ~r/use Plug\.Test/ or harness_src =~ ~r/import Plug\.Test/ ->
        base(:plug_selfcontained)

      true ->
        base(:pure_otp)
    end
  end

  defp base(archetype),
    do: %{archetype: archetype, prefix: nil, web_prefix: nil, otp_app: nil, db: :none}

  defp load_manifest(task_dir) do
    path = Path.join(task_dir, "manifest.exs")

    if File.regular?(path) do
      {map, _} = Code.eval_file(path)
      map
    else
      nil
    end
  end
end
