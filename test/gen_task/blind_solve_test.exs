defmodule GenTask.BlindSolveTest do
  use ExUnit.Case, async: false

  alias GenTask.{Config, Cycle, Reply, Variations}

  # Fake transports run IN the test process (Cycle.generate is synchronous), so they
  # can record what they saw via send(self(), …) and sequence replies via the
  # process dictionary.

  defmodule FakeOpusSolution do
    def call(_system, user, _cfg) do
      send(self(), {:opus_saw, user})

      {:ok, ~s(<file path="solution.ex">\ndefmodule Blind do\n  def go, do: :ok\nend\n</file>),
       %{}}
    end
  end

  defmodule FakeOpusJunkThenGood do
    def call(_system, user, _cfg) do
      send(self(), {:opus_saw, user})

      case Process.get(:fake_opus_calls, 0) do
        0 ->
          Process.put(:fake_opus_calls, 1)
          {:ok, "sorry, here is an explanation instead of files", %{}}

        _ ->
          {:ok,
           ~s(<file path="solution.ex">\ndefmodule Blind do\n  def go, do: :ok\nend\n</file>),
           %{}}
      end
    end
  end

  defmodule FakeOpusAlwaysJunk do
    def call(_system, _user, _cfg) do
      send(self(), :opus_called)
      {:ok, "no files here", %{}}
    end
  end

  setup do
    logs = Path.join(System.tmp_dir!(), "blind_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(logs)
    on_exit(fn -> File.rm_rf!(logs) end)
    Process.delete(:fake_opus_calls)
    %{logs: logs}
  end

  defp cfg(logs, fake), do: %Config{logs_dir: logs, opus: fake}

  describe "Cycle.generate/6" do
    test "parses and contract-validates a good reply", %{logs: logs} do
      assert {:ok, files} =
               Cycle.generate(
                 cfg(logs, FakeOpusSolution),
                 "t1",
                 "step",
                 "sys",
                 "user",
                 &Reply.validate_answer/1
               )

      assert files["solution.ex"] =~ "defmodule Blind"
    end

    test "reminds once on a contract miss, then succeeds", %{logs: logs} do
      assert {:ok, _files} =
               Cycle.generate(
                 cfg(logs, FakeOpusJunkThenGood),
                 "t1",
                 "step",
                 "sys",
                 "user",
                 &Reply.validate_answer/1
               )

      assert_received {:opus_saw, first}
      assert_received {:opus_saw, second}
      refute first =~ "Reminder:"
      assert second =~ "Reminder: return ONLY the requested <file> blocks"
    end

    test "gives up with {:contract, step} when retries are exhausted", %{logs: logs} do
      assert {:error, {:contract, "step"}} =
               Cycle.generate(
                 cfg(logs, FakeOpusAlwaysJunk),
                 "t1",
                 "step",
                 "sys",
                 "user",
                 &Reply.validate_answer/1
               )

      assert_received :opus_called
      assert_received :opus_called
      refute_received :opus_called
    end
  end

  describe "Variations.blind_solution/3" do
    test "the solver sees the variation prompt, never a harness", %{logs: logs} do
      prompt = "Write me an Elixir module called `Blind` with a `go/0` returning :ok."

      assert {:ok, solution} =
               Variations.blind_solution("001_002_x_01", prompt, cfg(logs, FakeOpusSolution))

      assert solution =~ "defmodule Blind"

      assert_received {:opus_saw, user}
      assert user =~ prompt
      # base_solve embeds the prompt + house style + output contract — no harness.
      refute user =~ "ExUnit"
      refute user =~ "test_harness"
    end

    test "propagates transport/contract failure as {:error, _}", %{logs: logs} do
      assert {:error, {:contract, "variation_blind_solve"}} =
               Variations.blind_solution("001_002_x_01", "prompt", cfg(logs, FakeOpusAlwaysJunk))
    end
  end
end
