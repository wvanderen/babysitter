defmodule Babysitter.Tmux.VerifierTest do
  use ExUnit.Case, async: true

  alias Babysitter.Tmux.Verifier

  describe "verify_tmux_available/0" do
    test "returns ok with version when tmux is installed" do
      assert {:ok, version} = Verifier.verify_tmux_available()
      assert is_binary(version)
      assert String.match?(version, ~r/^\d+\.\d+/)
    end

    test "returns error when command does not exist" do
      original_path = System.get_env("PATH")

      System.put_env("PATH", "/nonexistent")
      on_exit(fn -> System.put_env("PATH", original_path) end)

      assert {:error, :tmux_not_found} = Verifier.verify_tmux_available()
    end
  end

  describe "verify_tmux_available!/0" do
    test "returns version when tmux is installed" do
      assert version = Verifier.verify_tmux_available!()
      assert is_binary(version)
    end

    test "raises when tmux is not installed" do
      original_path = System.get_env("PATH")

      System.put_env("PATH", "/nonexistent")
      on_exit(fn -> System.put_env("PATH", original_path) end)

      assert_raise RuntimeError, ~r/tmux is not installed/, fn ->
        Verifier.verify_tmux_available!()
      end
    end
  end

  describe "installation_instructions/0" do
    test "returns installation instructions" do
      instructions = Verifier.installation_instructions()

      assert instructions =~ "macOS"
      assert instructions =~ "Ubuntu"
      assert instructions =~ "brew install tmux"
      assert instructions =~ "apt-get install tmux"
    end
  end
end
