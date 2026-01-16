# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.SnapshotVerifier do
  @moduledoc """
  Verifies RPC action snapshots match current code state.

  This module is called during codegen to ensure developers acknowledge
  interface changes by bumping version numbers.

  ## Verification Logic

  For each RPC action:
  1. Load the latest snapshot (if exists)
  2. Build a snapshot from current code state
  3. Compare hashes:
     - Contract hash changed → Require `min_version` bump
     - Version hash changed → Require `version` bump
     - No changes → OK

  If an action has no snapshot, a new one is created automatically.

  ## Error Messages

  When verification fails, clear instructions are provided:

      BREAKING CHANGE DETECTED in MyApp.Domain.list_todos
      Contract hash changed: a3f8c2d9 → b7e9d1f3

      Required: Bump min_version from 1 to 2

        rpc_action :list_todos, :read, min_version: 2, version: 2
  """

  alias AshTypescript.Rpc.Snapshot

  @type violation :: %{
          domain: module(),
          resource: module(),
          rpc_action_name: atom(),
          type: :contract_changed | :version_changed,
          current_hash: String.t(),
          snapshot_hash: String.t(),
          current_version: pos_integer(),
          current_min_version: pos_integer(),
          snapshot_version: pos_integer(),
          snapshot_min_version: pos_integer()
        }

  @doc """
  Verifies all RPC actions have valid snapshots.

  ## Parameters

  - `otp_app` - The OTP application atom
  - `resources_and_actions` - List of `{resource, action, rpc_action}` tuples

  ## Returns

  - `:ok` if all snapshots are valid
  - `{:error, violations}` with a list of actions that need version bumps
  - `{:ok, new_snapshots}` with snapshots to create for new actions
  """
  @spec verify_all(atom(), [{module(), map(), map()}]) ::
          :ok | {:error, [violation()]} | {:ok, :new_snapshots, [Snapshot.t()]}
  def verify_all(otp_app, resources_and_actions) do
    results =
      Enum.map(resources_and_actions, fn {resource, action, rpc_action} ->
        domain = Ash.Resource.Info.domain(resource)
        verify_one(otp_app, domain, resource, action, rpc_action)
      end)

    violations = Enum.filter(results, &match?({:violation, _}, &1)) |> Enum.map(&elem(&1, 1))
    new_snapshots = Enum.filter(results, &match?({:new, _}, &1)) |> Enum.map(&elem(&1, 1))

    cond do
      violations != [] ->
        {:error, violations}

      new_snapshots != [] ->
        {:ok, :new_snapshots, new_snapshots}

      true ->
        :ok
    end
  end

  @doc """
  Verifies a single RPC action's snapshot.

  ## Returns

  - `:ok` if snapshot matches
  - `{:violation, violation}` if version bump needed
  - `{:new, snapshot}` if this is a new action
  """
  @spec verify_one(atom(), module(), module(), map(), map()) ::
          :ok | {:violation, violation()} | {:new, Snapshot.t()}
  def verify_one(otp_app, domain, resource, action, rpc_action) do
    current = Snapshot.build(domain, resource, action, rpc_action)

    case Snapshot.load_latest(otp_app, domain, rpc_action.name) do
      {:ok, latest} ->
        verify_against_snapshot(current, latest, domain, resource, rpc_action)

      {:error, :not_found} ->
        {:new, current}

      {:error, reason} ->
        # Treat as new if we can't load the snapshot
        IO.warn(
          "Could not load snapshot for #{inspect(rpc_action.name)}: #{inspect(reason)}. Treating as new action."
        )

        {:new, current}
    end
  end

  defp verify_against_snapshot(current, latest, _domain, _resource, _rpc_action) do
    case Snapshot.compare(current, latest) do
      :unchanged ->
        :ok

      {:contract_changed, current_hash, snapshot_hash} ->
        # Breaking change - check if min_version was bumped
        if current.min_version > latest.min_version do
          # min_version was bumped, also check version was bumped
          if current.version > latest.version do
            # Version bumped correctly - create new snapshot
            {:new, current}
          else
            # min_version bumped but version not bumped - need to bump version too
            {:violation, build_violation(current, latest, :version_changed)}
          end
        else
          {:violation,
           build_violation(current, latest, :contract_changed, current_hash, snapshot_hash)}
        end

      {:version_changed, current_hash, snapshot_hash} ->
        # Non-breaking change - check if version was bumped
        if current.version > latest.version do
          # Version bumped correctly - create new snapshot
          {:new, current}
        else
          {:violation,
           build_violation(current, latest, :version_changed, current_hash, snapshot_hash)}
        end
    end
  end

  defp build_violation(current, latest, type, current_hash \\ nil, snapshot_hash \\ nil) do
    %{
      domain: current.domain,
      resource: current.resource,
      rpc_action_name: current.rpc_action_name,
      type: type,
      current_hash: current_hash || current.version_hash,
      snapshot_hash: snapshot_hash || latest.version_hash,
      current_version: current.version,
      current_min_version: current.min_version,
      snapshot_version: latest.version,
      snapshot_min_version: latest.min_version
    }
  end

  @doc """
  Formats violations into a human-readable error message.
  """
  @spec format_violations([violation()]) :: String.t()
  def format_violations(violations) do
    violation_messages =
      violations
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {violation, index} ->
        format_violation(violation, index)
      end)

    """
    RPC Action Snapshot Verification Failed
    =======================================

    #{violation_messages}

    After fixing the version numbers, run codegen again to create new snapshots.
    """
  end

  defp format_violation(violation, index) do
    case violation.type do
      :contract_changed ->
        required_min = violation.snapshot_min_version + 1
        required_version = max(violation.snapshot_version + 1, required_min)

        """
        #{index}. #{inspect(violation.domain)}.#{violation.rpc_action_name} (#{inspect(violation.resource)})

           BREAKING CHANGE DETECTED
           Contract hash changed: #{String.slice(violation.snapshot_hash, 0, 8)} → #{String.slice(violation.current_hash, 0, 8)}

           This indicates a breaking API change. Clients using the old interface
           will not be compatible.

           Required: Bump min_version from #{violation.snapshot_min_version} to #{required_min}
                     Bump version from #{violation.snapshot_version} to #{required_version}

           In your domain:

             rpc_action :#{violation.rpc_action_name}, :#{get_action_name(violation)}, min_version: #{required_min}, version: #{required_version}
        """

      :version_changed ->
        required_version = violation.snapshot_version + 1

        """
        #{index}. #{inspect(violation.domain)}.#{violation.rpc_action_name} (#{inspect(violation.resource)})

           NON-BREAKING CHANGE DETECTED
           Version hash changed: #{String.slice(violation.snapshot_hash, 0, 8)} → #{String.slice(violation.current_hash, 0, 8)}

           This indicates a non-breaking API change (e.g., new optional field).
           Existing clients remain compatible.

           Required: Bump version from #{violation.snapshot_version} to #{required_version}

           In your domain:

             rpc_action :#{violation.rpc_action_name}, :#{get_action_name(violation)}, version: #{required_version}
        """
    end
  end

  defp get_action_name(violation) do
    violation.rpc_action_name
  end
end
