defmodule Babysitter.CommitStrategy do
  @moduledoc """
  Configurable commit strategy that reads trigger and template from config.

  Supports three trigger types:
  - `stage_complete` - Commit after each stage completes successfully
  - `validation_pass` - Commit after validation passes
  - `manual` - Manual commits only (no automatic commits)

  ## Configuration

  Configure in `~/.config/babysitter/config.yaml`:

      git:
        commit_strategy:
          trigger: stage_complete
          message_template: |
            {{issue.id}}: {{issue.title}}

            {{stage.summary}}

  ## Examples

      CommitStrategy.maybe_commit(issue, stage: stage, validation_passed: true)
      CommitStrategy.get_trigger()
      CommitStrategy.get_template()
  """

  alias Babysitter.{CommitTrigger, Config, Git}

  @type trigger :: :stage_complete | :validation_pass | :manual
  @type error :: {:error, String.t()}

  @valid_triggers [:stage_complete, :validation_pass, :manual]

  @doc """
  Get the configured commit trigger.

  ## Examples

      iex> get_trigger()
      :stage_complete
  """
  @spec get_trigger() :: trigger()
  def get_trigger do
    config = Config.git()
    trigger_str = get_in(config, [:commit_strategy, :trigger]) || "stage_complete"

    trigger =
      trigger_str
      |> to_string()
      |> String.to_atom()

    if trigger in @valid_triggers do
      trigger
    else
      :stage_complete
    end
  end

  @doc """
  Get the configured commit message template.

  ## Examples

      iex> get_template()
      "{{issue.id}}: {{issue.title}}..."
  """
  @spec get_template() :: String.t() | nil
  def get_template do
    config = Config.git()
    get_in(config, [:commit_strategy, :message_template])
  end

  @doc """
  Check if automatic commits are enabled based on configured trigger.

  ## Examples

      iex> auto_commit_enabled?()
      true
  """
  @spec auto_commit_enabled?() :: boolean()
  def auto_commit_enabled? do
    get_trigger() != :manual
  end

  @doc """
  Execute a commit based on the configured strategy.

  This reads the trigger and template from config and executes
  the appropriate commit action.

  ## Parameters

  - `issue` - Issue map with id, title, etc.
  - `opts` - Additional options:
    - `:stage` - Stage map with id, name, summary
    - `:validation_passed` - Whether validation passed (default: true)
    - `:dry_run` - Preview without executing (default: false)
    - `:force` - Force commit even if trigger doesn't match (default: false)

  ## Examples

      iex> maybe_commit(%{id: "td-123"}, stage: %{summary: "Done"})
      {:ok, "a1b2c3d"}

      iex> maybe_commit(%{id: "td-123"}, dry_run: true)
      {:ok, "td-123: ..."}
  """
  @spec maybe_commit(map(), keyword()) :: {:ok, String.t()} | :skipped | error()
  def maybe_commit(issue, opts \\ []) do
    trigger = get_trigger()
    template = get_template()
    force = Keyword.get(opts, :force, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    opts =
      if template do
        Keyword.put(opts, :custom_template, template)
      else
        opts
      end

    should_commit =
      if force do
        true
      else
        should_commit?(trigger, opts)
      end

    if should_commit do
      execute_with_trigger(trigger, issue, opts)
    else
      if dry_run do
        {:ok, "(skipped - trigger condition not met)"}
      else
        :skipped
      end
    end
  end

  @doc """
  Execute a commit for stage completion.

  This checks if the configured trigger is `stage_complete` before committing.

  ## Examples

      iex> on_stage_complete(%{id: "td-123"}, stage: %{summary: "Done"})
      {:ok, "a1b2c3d"}
  """
  @spec on_stage_complete(map(), keyword()) :: {:ok, String.t()} | :skipped | error()
  def on_stage_complete(issue, opts \\ []) do
    trigger = get_trigger()

    if trigger == :stage_complete do
      maybe_commit(issue, opts)
    else
      :skipped
    end
  end

  @doc """
  Execute a commit for validation pass.

  This checks if the configured trigger is `validation_pass` before committing.

  ## Examples

      iex> on_validation_pass(%{id: "td-123"}, stage: %{summary: "Validated"})
      {:ok, "a1b2c3d"}
  """
  @spec on_validation_pass(map(), keyword()) :: {:ok, String.t()} | :skipped | error()
  def on_validation_pass(issue, opts \\ []) do
    trigger = get_trigger()

    if trigger == :validation_pass do
      maybe_commit(issue, Keyword.put(opts, :validation_passed, true))
    else
      :skipped
    end
  end

  @doc """
  Execute a manual commit.

  Always executes regardless of trigger setting.

  ## Examples

      iex> on_manual(%{id: "td-123"}, stage: %{summary: "Manual commit"})
      {:ok, "a1b2c3d"}
  """
  @spec on_manual(map(), keyword()) :: {:ok, String.t()} | error()
  def on_manual(issue, opts \\ []) do
    maybe_commit(issue, Keyword.put(opts, :force, true))
  end

  @doc """
  Check if a commit should be made based on trigger and conditions.

  ## Parameters

  - `trigger` - The trigger type to check
  - `opts` - Conditions:
    - `:has_changes` - Whether there are uncommitted changes
    - `:validation_passed` - Whether validation passed
    - `:stage_completed` - Whether a stage just completed

  ## Examples

      iex> should_commit?(:stage_complete, has_changes: true, stage_completed: true)
      true
  """
  @spec should_commit?(trigger(), keyword()) :: boolean()
  def should_commit?(trigger, opts \\ []) do
    has_changes = Keyword.get(opts, :has_changes, Git.has_changes?())
    validation_passed = Keyword.get(opts, :validation_passed, true)
    stage_completed = Keyword.get(opts, :stage_completed, true)

    case trigger do
      :stage_complete -> has_changes and stage_completed and validation_passed
      :validation_pass -> has_changes and validation_passed
      :manual -> false
    end
  end

  @doc """
  Get the effective trigger that would fire given current conditions.

  ## Examples

      iex> effective_trigger(has_changes: true, validation_passed: true)
      :stage_complete
  """
  @spec effective_trigger(keyword()) :: trigger() | :none
  def effective_trigger(opts \\ []) do
    trigger = get_trigger()

    if should_commit?(trigger, opts) do
      trigger
    else
      :none
    end
  end

  @doc """
  Preview the commit message without executing.

  ## Examples

      iex> preview(%{id: "td-123"}, stage: %{summary: "Preview"})
      {:ok, "td-123: Preview..."}
  """
  @spec preview(map(), keyword()) :: {:ok, String.t()}
  def preview(issue, opts \\ []) do
    maybe_commit(issue, Keyword.put(opts, :dry_run, true))
  end

  @doc """
  List valid trigger types.

  ## Examples

      iex> valid_triggers()
      [:stage_complete, :validation_pass, :manual]
  """
  @spec valid_triggers() :: [trigger()]
  def valid_triggers do
    @valid_triggers
  end

  defp execute_with_trigger(trigger, issue, opts) do
    template = Keyword.get(opts, :custom_template)

    if template do
      CommitTrigger.execute_with_template(template, issue, opts)
    else
      CommitTrigger.execute(trigger, issue, opts)
    end
  end
end
