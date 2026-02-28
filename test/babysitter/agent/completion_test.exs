defmodule Babysitter.Agent.CompletionTest do
  use ExUnit.Case, async: true

  alias Babysitter.Agent.Completion

  describe "check/2 with marker detection" do
    test "returns {:ok, :complete} when completion marker found" do
      output = "Task completed\nBABYSITTER_DONE\n"
      assert {:ok, :complete} = Completion.check(output, marker: "BABYSITTER_DONE")
    end

    test "returns {:ok, :complete} with regex pattern" do
      output = "All done ✓ Complete"
      assert {:ok, :complete} = Completion.check(output, marker: "BABYSITTER_DONE|✓ Complete")
    end

    test "returns {:continue, reason} when marker not found" do
      output = "Still working..."
      assert {:continue, :marker_not_found} = Completion.check(output, marker: "BABYSITTER_DONE")
    end

    test "handles nil marker (uses stability detection)" do
      output = "Any output"

      assert {:continue, :unstable} =
               Completion.check(output, marker: nil, stability_threshold: 5000)
    end

    test "handles empty marker (uses stability detection)" do
      output = "Any output"

      assert {:continue, :unstable} =
               Completion.check(output, marker: "", stability_threshold: 5000)
    end
  end

  describe "check/2 with stability detection" do
    test "returns {:ok, :stable} when output is stable" do
      output = "Final output"

      assert {:ok, :stable} =
               Completion.check(output, stability_threshold: 0, last_output: "Final output")
    end

    test "returns {:continue, :unstable} when output is changing" do
      output = "New output"

      assert {:continue, :unstable} =
               Completion.check(output,
                 stability_threshold: 5000,
                 last_output: "Old output",
                 stable_ms: 0
               )
    end

    test "returns {:ok, :stable} after stability threshold reached" do
      output = "Stable output"

      assert {:ok, :stable} =
               Completion.check(output,
                 stability_threshold: 5000,
                 last_output: "Stable output",
                 stable_ms: 5000
               )
    end
  end

  describe "wait_for_completion/3" do
    setup do
      session_name = "test-completion-#{:rand.uniform(1_000_000)}"
      :ok = Babysitter.Tmux.create_session(session_name)
      on_exit(fn -> Babysitter.Tmux.kill_session(session_name) end)
      {:ok, session_name: session_name}
    end

    test "returns {:ok, output} when marker found", %{session_name: session_name} do
      Babysitter.Tmux.send_keys(session_name, "echo 'BABYSITTER_DONE'")
      Process.sleep(100)

      assert {:ok, output} =
               Completion.wait_for_completion(session_name,
                 marker: "BABYSITTER_DONE",
                 timeout: 1000
               )

      assert String.contains?(output, "BABYSITTER_DONE")
    end

    test "returns {:error, :timeout} when marker not found", %{session_name: session_name} do
      assert {:error, :timeout} =
               Completion.wait_for_completion(session_name, marker: "NEVER_APPEARS", timeout: 50)
    end

    test "falls back to stability when no marker configured", %{session_name: session_name} do
      Babysitter.Tmux.send_keys(session_name, "echo 'stable'")
      Process.sleep(100)

      assert {:ok, _output} =
               Completion.wait_for_completion(session_name,
                 marker: "",
                 stability_threshold: 0,
                 timeout: 500
               )
    end
  end

  describe "normalize_for_stability/1" do
    test "strips ANSI codes" do
      output = "\e[32mColored text\e[0m"
      assert Completion.normalize_for_stability(output) == "Colored text"
    end

    test "strips box drawing characters" do
      output = "┌─┐\n│X│\n└─┘"
      normalized = Completion.normalize_for_stability(output)
      refute String.contains?(normalized, "┌")
      refute String.contains?(normalized, "│")
    end

    test "trims whitespace" do
      output = "  text  \n"
      assert Completion.normalize_for_stability(output) == "text"
    end
  end

  describe "config_for_agent/1" do
    test "returns completion config for known agent" do
      config = Completion.config_for_agent(:pi)
      assert is_map(config)
      assert Map.has_key?(config, :marker) or Map.has_key?(config, :stability_threshold)
    end

    test "returns defaults for unknown agent" do
      config = Completion.config_for_agent(:unknown_agent)
      assert is_map(config)
    end
  end

  describe "default_timeout/0" do
    test "returns default timeout value" do
      assert Completion.default_timeout() == 300_000
    end
  end

  describe "default_stability_threshold/0" do
    test "returns default stability threshold" do
      assert Completion.default_stability_threshold() == 10_000
    end
  end

  describe "calculate_stable_ms/3" do
    test "increments when output is stable" do
      output = "same"
      assert Completion.calculate_stable_ms(output, output, 1000) == 1500
    end

    test "resets to 0 when output changes" do
      assert Completion.calculate_stable_ms("new", "old", 1000) == 0
    end

    test "handles nil last_output" do
      assert Completion.calculate_stable_ms("output", nil, 0) == 0
    end
  end
end
