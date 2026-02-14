defmodule Babysitter.CommitTrigger do
  @moduledoc """
  Execute commits based on triggers with context-aware message generation.

  Supports three trigger types:
  - `:stage_complete` - After a stage finishes successfully
  - `:validation_pass` - After validation passes
  - `:manual` - Manual commit triggered by user

  ## Options

  - `:dry_run` - Preview commit without executing (default: false)
  - `:allow_empty` - Allow commits with no changes (default: false)
  - `:custom_template` - Override default template for trigger
  - `:files` - List of specific files to stage (default: all changed)

  ## Examples

      CommitTrigger.execute(:stage_complete, issue, stage: stage)
      CommitTrigger.on_stage_complete(issue, stage: stage, dry_run: true)
      CommitTrigger.preview(:manual, issue, stage: stage)
  """

  alias Babysitter.{CommitTemplates, Git}

  @type trigger :: :stage_complete | :validation_pass | :manual
  @type error :: {:error, String.t()}

  @doc """
  Execute a commit based on trigger type.

  ## Parameters

  - `trigger` - The trigger type atom
  - `issue` - Issue map with id, title, etc.
  - `opts` - Additional options and context:
    - `:stage` - Stage map with id, name, summary
    - `:dry_run` - Preview without executing
    - `:allow_empty` - Allow empty commits
    - `:custom_template` - Custom template string
    - `:files` - Specific files to stage

  ## Examples

      iex> CommitTrigger.execute(:stage_complete, %{id: "td-123"}, stage: %{summary: "Done"})
      {:ok, "a1b2c3d"}
  """
  @spec execute(trigger(), map(), keyword()) :: {:ok, String.t()} | error()
  def execute(trigger, issue, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    custom_template = Keyword.get(opts, :custom_template)

    message =
      if custom_template do
        CommitTemplates.build_with_template(custom_template, issue, opts)
      else
        CommitTemplates.build_message(trigger, issue, opts)
      end

    if dry_run do
      {:ok, message}
    else
      do_commit(message, opts)
    end
  end

  @doc """
  Execute commit with a custom template.

  ## Examples

      iex> CommitTrigger.execute_with_template("Issue {{issue.id}}", issue, stage: stage)
      {:ok, "a1b2c3d"}
  """
  @spec execute_with_template(String.t(), map(), keyword()) :: {:ok, String.t()} | error()
  def execute_with_template(template, issue, opts \\ []) do
    execute(:manual, issue, Keyword.put(opts, :custom_template, template))
  end

  @doc """
  Preview commit message without executing.

  ## Examples

      iex> CommitTrigger.preview(:stage_complete, issue, stage: stage)
      {:ok, "Completed td-123: ..."}
  """
  @spec preview(trigger(), map(), keyword()) :: {:ok, String.t()}
  def preview(trigger, issue, opts \\ []) do
    execute(trigger, issue, Keyword.put(opts, :dry_run, true))
  end

  @doc """
  Stage files only, without committing.

  ## Examples

      iex> CommitTrigger.stage_only(files: ["lib/foo.ex"])
      :ok
  """
  @spec stage_only(keyword()) :: :ok | error()
  def stage_only(opts \\ []) do
    files = Keyword.get(opts, :files)

    add_opts =
      if files do
        [files: files]
      else
        [all: true]
      end

    Git.add(add_opts)
  end

  @doc """
  Convenience function for stage_complete trigger.

  ## Examples

      iex> CommitTrigger.on_stage_complete(issue, stage: stage)
      {:ok, "a1b2c3d"}
  """
  @spec on_stage_complete(map(), keyword()) :: {:ok, String.t()} | error()
  def on_stage_complete(issue, opts \\ []) do
    execute(:stage_complete, issue, opts)
  end

  @doc """
  Convenience function for validation_pass trigger.

  ## Examples

      iex> CommitTrigger.on_validation_pass(issue, stage: stage)
      {:ok, "a1b2c3d"}
  """
  @spec on_validation_pass(map(), keyword()) :: {:ok, String.t()} | error()
  def on_validation_pass(issue, opts \\ []) do
    execute(:validation_pass, issue, opts)
  end

  @doc """
  Convenience function for manual trigger.

  ## Examples

      iex> CommitTrigger.on_manual(issue, stage: stage)
      {:ok, "a1b2c3d"}
  """
  @spec on_manual(map(), keyword()) :: {:ok, String.t()} | error()
  def on_manual(issue, opts \\ []) do
    execute(:manual, issue, opts)
  end

  @doc """
  Check if a commit should be triggered based on conditions.

  ## Examples

      iex> CommitTrigger.should_trigger?(:stage_complete, has_changes: true, validation_passed: true)
      true
  """
  @spec should_trigger?(trigger(), keyword()) :: boolean()
  def should_trigger?(trigger, opts \\ []) do
    has_changes = Keyword.get(opts, :has_changes, Git.has_changes?())
    validation_passed = Keyword.get(opts, :validation_passed, true)

    case trigger do
      :stage_complete -> has_changes and validation_passed
      :validation_pass -> has_changes and validation_passed
      :manual -> has_changes
    end
  end

  defp do_commit(message, opts) do
    allow_empty = Keyword.get(opts, :allow_empty, false)
    files = Keyword.get(opts, :files)

    add_opts =
      if files do
        [files: files]
      else
        [all: true]
      end

    with :ok <- Git.add(add_opts),
         :ok <- Git.commit(message: message, allow_empty: allow_empty) do
      case Git.last_commit(short: true) do
        hash when is_binary(hash) -> {:ok, hash}
        error -> error
      end
    end
  end
end
