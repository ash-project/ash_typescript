# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule Mix.Tasks.AshTypescript.GenerateSnapshots do
  @moduledoc """
  Generates or regenerates RPC action snapshots.

  Snapshots are JSON files stored in `priv/rpc_action_snapshots/{Domain.Name}/{action_name}/`
  that capture the interface state of RPC actions for version skew detection.

  ## Usage

      # Generate snapshots for all new actions (normal workflow)
      mix ash_typescript.generate_snapshots

      # Force regenerate all snapshots (after bumping versions)
      mix ash_typescript.generate_snapshots --force

      # Preview what would be generated
      mix ash_typescript.generate_snapshots --dry-run

      # Generate for a specific domain only
      mix ash_typescript.generate_snapshots --domain MyApp.Domain

  ## Options

    * `--force` - Regenerate snapshots for all actions, even if they already exist.
      Use this after bumping version numbers to create new snapshots.

    * `--dry-run` - Show what snapshots would be created without writing files.

    * `--domain` - Only process actions from the specified domain.

  ## Examples

      # After making a breaking change and bumping min_version:
      mix ash_typescript.generate_snapshots --force

      # Check what would be generated:
      mix ash_typescript.generate_snapshots --dry-run
  """

  @shortdoc "Generates RPC action snapshots for version skew detection"

  use Mix.Task

  alias AshTypescript.Rpc.Codegen.RpcConfigCollector
  alias AshTypescript.Rpc.{Snapshot, SnapshotVerifier}

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          force: :boolean,
          dry_run: :boolean,
          domain: :string
        ]
      )

    otp_app = Mix.Project.config()[:app]

    resources_and_actions = RpcConfigCollector.get_rpc_resources_and_actions(otp_app)

    # Filter by domain if specified
    resources_and_actions =
      if domain_filter = opts[:domain] do
        domain_module = String.to_atom("Elixir.#{domain_filter}")

        Enum.filter(resources_and_actions, fn {resource, _action, _rpc_action} ->
          Ash.Resource.Info.domain(resource) == domain_module
        end)
      else
        resources_and_actions
      end

    if opts[:force] do
      generate_all_snapshots(otp_app, resources_and_actions, opts)
    else
      generate_new_snapshots(otp_app, resources_and_actions, opts)
    end
  end

  defp generate_all_snapshots(otp_app, resources_and_actions, opts) do
    dry_run? = opts[:dry_run]

    snapshots =
      Enum.map(resources_and_actions, fn {resource, action, rpc_action} ->
        domain = Ash.Resource.Info.domain(resource)
        Snapshot.build(domain, resource, action, rpc_action)
      end)

    if dry_run? do
      IO.puts("Would generate #{length(snapshots)} snapshot(s):\n")

      Enum.each(snapshots, fn snapshot ->
        IO.puts(
          "  - #{snapshot.rpc_action_name} (version: #{snapshot.version}, min_version: #{snapshot.min_version})"
        )

        IO.puts("    Domain: #{snapshot.domain}")
        IO.puts("    Contract hash: #{snapshot.contract_hash}")
        IO.puts("    Version hash: #{snapshot.version_hash}")
        IO.puts("")
      end)
    else
      Enum.each(snapshots, fn snapshot ->
        case Snapshot.save(otp_app, snapshot) do
          :ok ->
            IO.puts(
              "Created snapshot for #{snapshot.rpc_action_name} (version: #{snapshot.version})"
            )

          {:error, reason} ->
            IO.puts(
              :stderr,
              "Failed to save snapshot for #{snapshot.rpc_action_name}: #{inspect(reason)}"
            )
        end
      end)

      IO.puts("\nGenerated #{length(snapshots)} snapshot(s)")
    end
  end

  defp generate_new_snapshots(otp_app, resources_and_actions, opts) do
    dry_run? = opts[:dry_run]

    case SnapshotVerifier.verify_all(otp_app, resources_and_actions) do
      :ok ->
        IO.puts("All snapshots are up to date. No new snapshots needed.")

      {:ok, :new_snapshots, new_snapshots} ->
        if dry_run? do
          IO.puts("Would generate #{length(new_snapshots)} new snapshot(s):\n")

          Enum.each(new_snapshots, fn snapshot ->
            IO.puts("  - #{snapshot.rpc_action_name} (version: #{snapshot.version})")
            IO.puts("    Domain: #{snapshot.domain}")
            IO.puts("")
          end)
        else
          Enum.each(new_snapshots, fn snapshot ->
            case Snapshot.save(otp_app, snapshot) do
              :ok ->
                IO.puts(
                  "Created snapshot for #{snapshot.rpc_action_name} (version: #{snapshot.version})"
                )

              {:error, reason} ->
                IO.puts(
                  :stderr,
                  "Failed to save snapshot for #{snapshot.rpc_action_name}: #{inspect(reason)}"
                )
            end
          end)

          IO.puts("\nGenerated #{length(new_snapshots)} new snapshot(s)")
        end

      {:error, violations} ->
        IO.puts(:stderr, SnapshotVerifier.format_violations(violations))

        Mix.raise(
          "Snapshot verification failed. Please fix version numbers before generating snapshots."
        )
    end
  end
end
