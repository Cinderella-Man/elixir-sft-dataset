defmodule EvalTask.Fim do
  @moduledoc """
  Fill-in-the-middle (FIM) reconstruction.

  A FIM subtask dir (`<a>_<b>_<name>_0N`, N ≥ 2) holds only a `prompt.md` (the whole
  module with one function replaced by a `# TODO` marker) and a `solution.ex` (that
  one function). The parent `<a>_<b>_<name>_01` dir holds the real `test_harness.exs`.

  To test a candidate: extract the skeleton from the FIM `prompt.md`, splice the
  candidate at the marker, and run the parent's harness against the reconstructed
  module. Reconstruction uses the **prompt skeleton** (not the `_01` module), because
  `_01` modules drift after FIM extraction.
  """

  @todo ~r/#\s*TODO/i
  @skeleton ~r/```elixir\n(.*?)\n```/s

  @doc "The parent `_01` directory for a FIM dir under `tasks/`."
  @spec parent_dir(String.t()) :: String.t()
  def parent_dir(fim_dir) do
    base = Path.basename(fim_dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    Path.join(Path.dirname(fim_dir), parent)
  end

  @doc "True if `dir` is a FIM subtask (no harness of its own, prompt has a TODO marker)."
  @spec fim_dir?(String.t()) :: boolean()
  def fim_dir?(dir) do
    not File.regular?(Path.join(dir, "test_harness.exs")) and
      File.regular?(Path.join(dir, "prompt.md")) and
      String.match?(File.read!(Path.join(dir, "prompt.md")), @todo)
  end

  @doc """
  Reconstruct the full module from a FIM `prompt.md` skeleton and a candidate.

  The candidate may be the bare function, a fenced function, or a whole module
  (if it already contains `defmodule`, it is used verbatim). Returns the module
  source string, or raises if the skeleton/marker cannot be found.
  """
  @spec reconstruct(String.t(), String.t()) :: String.t()
  def reconstruct(prompt_md, candidate_raw) do
    candidate = extract_candidate(candidate_raw)

    if String.contains?(candidate, "defmodule") do
      candidate
    else
      skeleton = extract_skeleton(prompt_md)
      splice(skeleton, candidate)
    end
  end

  @doc "Strip a wrapping ```` ```elixir ```` fence from a model response, if present."
  @spec extract_candidate(String.t()) :: String.t()
  def extract_candidate(raw) do
    case Regex.run(~r/```(?:elixir)?\n(.*?)\n```/s, raw) do
      [_, code] -> code
      _ -> raw
    end
  end

  defp extract_skeleton(prompt_md) do
    case Regex.run(@skeleton, prompt_md) do
      [_, code] -> code
      _ -> raise "FIM prompt has no ```elixir skeleton fence"
    end
  end

  @doc """
  Splice a candidate function into a skeleton at the `# TODO` marker.

  Handles both conventions:
  * stub-body — `def SIG do  # TODO  end` → replace the enclosing `def…end`
  * placeholder-line — `#TODO defp foo` → replace just that line
  """
  @spec splice(String.t(), String.t()) :: String.t()
  def splice(skeleton, candidate) do
    lines = String.split(skeleton, "\n")
    marker_idx = Enum.find_index(lines, &String.match?(&1, @todo)) || raise "no # TODO marker"
    marker_line = Enum.at(lines, marker_idx)
    remainder = Regex.replace(~r/^\s*#\s*TODO:?/i, marker_line, "") |> String.trim()

    {lo, hi} =
      if remainder == "" do
        def_idx = scan_up_for_def(lines, marker_idx)
        indent = Regex.run(~r/^(\s*)/, Enum.at(lines, def_idx)) |> hd()
        end_idx = scan_down_for_end(lines, marker_idx, indent)
        {def_idx, end_idx}
      else
        {marker_idx, marker_idx}
      end

    (Enum.slice(lines, 0, lo) ++ [candidate] ++ Enum.slice(lines, (hi + 1)..-1//1))
    |> Enum.join("\n")
  end

  @doc """
  Produce a mutant of a candidate function: every clause body replaced with
  `raise`. Used by the validator's mutation check — if the parent harness still
  passes with this mutant spliced in, the FIM target is under-tested.
  """
  @spec mutate(String.t()) :: String.t()
  def mutate(candidate) do
    candidate
    |> extract_candidate()
    |> Code.string_to_quoted!()
    |> Macro.prewalk(fn
      {d, m, [head, kw]} when d in [:def, :defp, :defmacro, :defmacrop] and is_list(kw) ->
        if Keyword.has_key?(kw, :do),
          do: {d, m, [head, [do: quote(do: raise("MUTATION"))]]},
          else: {d, m, [head, kw]}

      other ->
        other
    end)
    |> Macro.to_string()
  rescue
    _ -> "raise \"MUTATION\""
  end

  defp scan_up_for_def(lines, from) do
    Enum.reduce_while((from - 1)..0//-1, nil, fn j, _ ->
      if String.match?(Enum.at(lines, j), ~r/^\s*(def|defp|defmacro|defmacrop)\s/),
        do: {:halt, j},
        else: {:cont, nil}
    end) || raise "no enclosing def above # TODO"
  end

  defp scan_down_for_end(lines, from, indent) do
    Enum.reduce_while((from + 1)..(length(lines) - 1), nil, fn j, _ ->
      if Enum.at(lines, j) == indent <> "end", do: {:halt, j}, else: {:cont, nil}
    end) || raise "no matching end for the stubbed def"
  end
end
