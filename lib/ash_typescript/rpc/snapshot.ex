# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Snapshot do
  @moduledoc """
  Handles RPC action snapshot creation, storage, and comparison.

  Snapshots are JSON files stored in `priv/rpc_action_snapshots/{Domain.Name}/{action_name}/`
  that capture the interface state of RPC actions for version skew detection.

  The domain folder uses the full module name (e.g., `MyApp.Domain`) to ensure uniqueness
  across different namespaces.

  ## Snapshot Contents

  Each snapshot contains:
  - Domain, resource, and action identifiers
  - Declared version and min_version from DSL
  - Contract and version hashes
  - Full contract and version signatures (the data used to compute hashes)
  - Creation timestamp

  ## Usage

      # Build a snapshot from current code state
      snapshot = Snapshot.build(domain, resource, action, rpc_action)

      # Save to disk
      Snapshot.save(otp_app, snapshot)

      # Load latest snapshot
      {:ok, snapshot} = Snapshot.load_latest(otp_app, domain, rpc_action_name)

      # Compare current state against snapshot
      case Snapshot.compare(current, latest) do
        :unchanged -> # No changes
        {:version_changed, _, _} -> # Non-breaking change, bump version
        {:contract_changed, _, _} -> # Breaking change, bump min_version
        :new_action -> # New action, will auto-create snapshot
      end
  """

  alias AshTypescript.Rpc.Action.Metadata.Signature

  defstruct [
    :domain,
    :resource,
    :rpc_action_name,
    :action_name,
    :action_type,
    :version,
    :min_version,
    :contract_hash,
    :version_hash,
    :contract_signature,
    :version_signature,
    :created_at
  ]

  @type t :: %__MODULE__{
          domain: String.t(),
          resource: String.t(),
          rpc_action_name: atom(),
          action_name: atom(),
          action_type: atom(),
          version: pos_integer(),
          min_version: pos_integer(),
          contract_hash: String.t(),
          version_hash: String.t(),
          contract_signature: map(),
          version_signature: map(),
          created_at: String.t()
        }

  @type comparison_result ::
          :unchanged
          | {:version_changed, String.t(), String.t()}
          | {:contract_changed, String.t(), String.t()}
          | :new_action

  @doc """
  Builds a snapshot from the current resource/action/rpc_action state.

  ## Parameters

  - `domain` - The domain module
  - `resource` - The resource module
  - `action` - The Ash action struct
  - `rpc_action` - The RPC action configuration

  ## Returns

  A `%Snapshot{}` struct containing all interface information and computed hashes.
  """
  @spec build(module(), module(), map(), map()) :: t()
  def build(domain, resource, action, rpc_action) do
    contract_sig = Signature.build_contract(resource, action, rpc_action)
    version_sig = Signature.build_version(resource, action, rpc_action)

    contract_hash = Signature.hash(contract_sig)
    version_hash = Signature.hash(version_sig)

    %__MODULE__{
      domain: inspect(domain),
      resource: inspect(resource),
      rpc_action_name: rpc_action.name,
      action_name: action.name,
      action_type: action.type,
      version: Map.get(rpc_action, :version, 1),
      min_version: Map.get(rpc_action, :min_version, 1),
      contract_hash: contract_hash,
      version_hash: version_hash,
      contract_signature: Map.from_struct(contract_sig),
      version_signature: Map.from_struct(version_sig),
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @doc """
  Serializes a snapshot to JSON string.

  Keys are sorted for deterministic output.
  """
  @spec to_json(t()) :: String.t()
  def to_json(%__MODULE__{} = snapshot) do
    snapshot
    |> Map.from_struct()
    |> to_ordered_object()
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Deserializes JSON string to a snapshot struct.
  """
  @spec from_json(String.t()) :: {:ok, t()} | {:error, term()}
  def from_json(json_string) do
    case Jason.decode(json_string) do
      {:ok, data} ->
        {:ok, from_map(data)}

      {:error, reason} ->
        {:error, {:json_decode_error, reason}}
    end
  end

  @doc """
  Gets the base snapshots directory path for an OTP app.

  Returns `{app_priv_dir}/rpc_action_snapshots` or uses the configured path.
  """
  @spec snapshots_dir(atom()) :: String.t()
  def snapshots_dir(otp_app) do
    configured_path = Application.get_env(:ash_typescript, :rpc_snapshots_path)

    if configured_path do
      configured_path
    else
      Path.join(Mix.Project.deps_paths()[otp_app] || File.cwd!(), "priv/rpc_action_snapshots")
    end
  end

  @doc """
  Gets the directory path for a specific action's snapshots.

  Returns `{snapshots_dir}/{domain_name}/{action_name}/`
  """
  @spec action_snapshots_dir(atom(), String.t() | module(), atom()) :: String.t()
  def action_snapshots_dir(otp_app, domain, rpc_action_name) do
    base_dir = snapshots_dir(otp_app)
    domain_name = domain_to_folder_name(domain)
    action_name = Atom.to_string(rpc_action_name)

    Path.join([base_dir, domain_name, action_name])
  end

  defp domain_to_folder_name(domain) when is_atom(domain) do
    domain
    |> Atom.to_string()
    |> String.trim_leading("Elixir.")
  end

  defp domain_to_folder_name(domain) when is_binary(domain) do
    String.trim_leading(domain, "Elixir.")
  end

  @doc """
  Loads the latest snapshot for an action.

  Returns `{:ok, snapshot}` if found, or `{:error, :not_found}` if no snapshot exists.
  """
  @spec load_latest(atom(), String.t() | module(), atom()) :: {:ok, t()} | {:error, :not_found}
  def load_latest(otp_app, domain, rpc_action_name) do
    dir = action_snapshots_dir(otp_app, domain, rpc_action_name)

    if File.exists?(dir) do
      case list_snapshot_files(dir) do
        [] ->
          {:error, :not_found}

        files ->
          # Get the most recent snapshot (highest timestamp)
          latest_file = Enum.max(files)
          file_path = Path.join(dir, latest_file)

          case File.read(file_path) do
            {:ok, content} ->
              from_json(content)

            {:error, reason} ->
              {:error, {:file_read_error, reason}}
          end
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Saves a new snapshot to disk.

  Creates the directory structure if it doesn't exist.
  Uses a 14-digit timestamp for the filename (YYYYMMDDHHMMSS.json).
  """
  @spec save(atom(), t()) :: :ok | {:error, term()}
  def save(otp_app, %__MODULE__{} = snapshot) do
    dir = action_snapshots_dir(otp_app, snapshot.domain, snapshot.rpc_action_name)
    File.mkdir_p!(dir)

    timestamp = generate_timestamp()
    filename = "#{timestamp}.json"
    file_path = Path.join(dir, filename)
    json = to_json(snapshot)

    case File.write(file_path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, {:file_write_error, reason}}
    end
  end

  @doc """
  Compares current snapshot against the latest saved snapshot.

  ## Returns

  - `:unchanged` - No changes detected
  - `{:version_changed, current_hash, snapshot_hash}` - Non-breaking change (version hash differs)
  - `{:contract_changed, current_hash, snapshot_hash}` - Breaking change (contract hash differs)
  - `:new_action` - No existing snapshot (this is a new action)
  """
  @spec compare(t(), t() | nil) :: comparison_result()
  def compare(_current, nil), do: :new_action

  def compare(%__MODULE__{} = current, %__MODULE__{} = snapshot) do
    cond do
      current.contract_hash != snapshot.contract_hash ->
        {:contract_changed, current.contract_hash, snapshot.contract_hash}

      current.version_hash != snapshot.version_hash ->
        {:version_changed, current.version_hash, snapshot.version_hash}

      true ->
        :unchanged
    end
  end

  @doc """
  Lists all snapshot files in a directory.

  Returns filenames matching the pattern `YYYYMMDDHHMMSS.json`.
  """
  @spec list_snapshot_files(String.t()) :: [String.t()]
  def list_snapshot_files(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&snapshot_filename?/1)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Private Helpers
  # ─────────────────────────────────────────────────────────────────

  defp snapshot_filename?(filename) do
    # Match 14-digit timestamp followed by .json
    Regex.match?(~r/^\d{14}\.json$/, filename)
  end

  defp generate_timestamp do
    {{year, month, day}, {hour, minute, second}} = :calendar.universal_time()

    :io_lib.format("~4..0B~2..0B~2..0B~2..0B~2..0B~2..0B", [
      year,
      month,
      day,
      hour,
      minute,
      second
    ])
    |> IO.iodata_to_binary()
  end

  defp from_map(data) do
    %__MODULE__{
      domain: Map.get(data, "domain"),
      resource: Map.get(data, "resource"),
      rpc_action_name: string_to_atom(Map.get(data, "rpc_action_name")),
      action_name: string_to_atom(Map.get(data, "action_name")),
      action_type: string_to_atom(Map.get(data, "action_type")),
      version: Map.get(data, "version"),
      min_version: Map.get(data, "min_version"),
      contract_hash: Map.get(data, "contract_hash"),
      version_hash: Map.get(data, "version_hash"),
      contract_signature: Map.get(data, "contract_signature"),
      version_signature: Map.get(data, "version_signature"),
      created_at: Map.get(data, "created_at")
    }
  end

  defp string_to_atom(nil), do: nil
  defp string_to_atom(str) when is_binary(str), do: String.to_atom(str)
  defp string_to_atom(atom) when is_atom(atom), do: atom

  # Convert to ordered structure for deterministic JSON
  defp to_ordered_object(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), to_ordered_object(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Jason.OrderedObject.new()
  end

  defp to_ordered_object(list) when is_list(list) do
    Enum.map(list, &to_ordered_object/1)
  end

  defp to_ordered_object(tuple) when is_tuple(tuple) do
    # Convert tuples to lists for JSON serialization
    tuple
    |> Tuple.to_list()
    |> Enum.map(&to_ordered_object/1)
  end

  defp to_ordered_object(%Regex{} = regex) do
    # Convert Regex to its source string for JSON serialization
    Regex.source(regex)
  end

  defp to_ordered_object(atom) when is_atom(atom) and not is_nil(atom) and not is_boolean(atom) do
    Atom.to_string(atom)
  end

  defp to_ordered_object(value), do: value
end
