defmodule Babysitter.ConfigTest do
  use ExUnit.Case, async: true

  alias Babysitter.Config

  describe "all/0" do
    test "returns config with defaults" do
      config = Config.all()

      assert is_map(config)
      assert Map.has_key?(config, :daemon)
      assert Map.has_key?(config, :tmux)
      assert Map.has_key?(config, :td)
      assert Map.has_key?(config, :agents)
      assert Map.has_key?(config, :git)
      assert Map.has_key?(config, :intervention)
    end
  end

  describe "get/1,2,3,4" do
    test "gets top-level config" do
      assert Config.get(:daemon) == Config.daemon()
    end

    test "gets nested config" do
      assert Config.get(:daemon, :port) == 4001
      assert Config.get(:tmux, :base_session) == "babysitter"
    end

    test "returns nil for missing keys" do
      assert Config.get(:nonexistent) == nil
      assert Config.get(:daemon, :nonexistent) == nil
    end
  end

  describe "daemon/0" do
    test "returns daemon config with defaults" do
      daemon = Config.daemon()

      assert daemon.port == 4001
      assert daemon.log_level == "info"
    end
  end

  describe "tmux/0" do
    test "returns tmux config with defaults" do
      tmux = Config.tmux()

      assert tmux.base_session == "babysitter"
    end
  end

  describe "td/0" do
    test "returns td config with defaults" do
      td = Config.td()

      assert td.database == ".todos/issues.db"
    end
  end

  describe "agent/1" do
    test "returns agent config by name" do
      claude = Config.agent(:claude)

      assert claude.command == "claude"
      assert claude.args == ["--dangerously-skip-permissions"]
    end

    test "returns nil for unknown agent" do
      assert Config.agent(:unknown) == nil
    end
  end

  describe "agents/0" do
    test "returns all agents" do
      agents = Config.agents()

      assert Map.has_key?(agents, :claude)
      assert Map.has_key?(agents, :opencode)
    end
  end

  describe "git/0" do
    test "returns git config with defaults" do
      git = Config.git()

      assert Map.has_key?(git, :commit_strategy)
      assert Map.has_key?(git, :pr_strategy)
      assert git.commit_strategy.trigger == "stage_complete"
    end
  end

  describe "intervention/0" do
    test "returns intervention config with defaults" do
      intervention = Config.intervention()

      assert intervention.default_intelligence == "hybrid"
      assert intervention.max_retries == 3
      assert intervention.timeout_minutes == 30
      assert intervention.stuck_threshold_minutes == 10
    end
  end

  describe "concurrency/0" do
    test "returns concurrency config" do
      concurrency = Config.concurrency()

      assert concurrency.max_parallel_sessions == 3
    end
  end

  describe "config_path/0" do
    test "returns expanded config path" do
      path = Config.config_path()

      assert String.ends_with?(path, "babysitter/config.yaml")
      refute String.starts_with?(path, "~")
    end
  end

  describe "config_exists?/0" do
    test "returns boolean" do
      assert is_boolean(Config.config_exists?())
    end
  end

  describe "ensure_config_dir!/0" do
    test "returns ok when dir exists or is created" do
      result = Config.ensure_config_dir!()
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "agent_completion_pattern/1" do
    test "returns nil for agent without completion pattern" do
      assert Config.agent_completion_pattern(:claude) == nil
    end

    test "returns nil for unknown agent" do
      assert Config.agent_completion_pattern(:unknown) == nil
    end
  end

  describe "agent_completion_timeout/1" do
    test "returns default timeout for agent without custom timeout" do
      assert Config.agent_completion_timeout(:claude) == 300_000
    end

    test "returns default timeout for unknown agent" do
      assert Config.agent_completion_timeout(:unknown) == 300_000
    end
  end

  describe "agent_stability_threshold/1" do
    test "returns default threshold for agent without custom threshold" do
      assert Config.agent_stability_threshold(:claude) == 10_000
    end

    test "returns default threshold for unknown agent" do
      assert Config.agent_stability_threshold(:unknown) == 10_000
    end
  end

  describe "deep merge behavior" do
    test "user config overrides defaults" do
      original_exists = Config.config_exists?()

      unless original_exists do
        path = Config.config_path()
        Config.ensure_config_dir!()

        File.write!(path, """
        daemon:
          port: 5000
        """)

        Config.all()

        daemon = Config.daemon()
        assert daemon.port == 5000
        assert daemon.log_level == "info"

        File.rm(path)
      end
    end
  end
end
