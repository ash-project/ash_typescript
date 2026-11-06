# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest.Verifiers.VerifyRpc do
  @moduledoc """
  Validates the structural consistency of `typescript_rpc` configuration against
  the generated manifest.

  Checks per RPC action:

    * The referenced action exists on the resource.
    * The action (and any `read_action` override) is `public?: true`.
    * `:get?` and `:get_by` options are coherent (read-only, mutually exclusive,
      `get_by` references real attributes).
    * `:allowed_loads` / `:denied_loads` are mutually exclusive, and every path
      they name is a load path (`AshTypescript.Manifest.LoadPaths`).
    * Each public relationship's destination has a public read action.

  Also enforces cross-domain uniqueness of typed query names (a duplicate RPC
  action name fails earlier, in ash_rpc's decorator).
  The names generated for RPC actions and typed queries, and every client name,
  are checked when the manifest compiles (`AshTypescript.Manifest.NameCheck`).

  Reads `rpc_configs` (raw per-resource RPC config including typed_queries) from
  the manifest module's persisted state so resources that are reachability roots
  without rpc_actions still get their typed_queries validated.
  """
  use Spark.Dsl.Verifier

  alias AshTypescript.Manifest.LoadPaths
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    do_verify(
      Verifier.get_persisted(dsl, :rpc_configs) || [],
      {Verifier.get_persisted(dsl, :resource_lookup), Verifier.get_persisted(dsl, :type_lookup)}
    )
  end

  defp do_verify(rpc_configs, lookups) do
    with :ok <- verify_unique_names_across_domains(rpc_configs),
         :ok <- verify_typescript_resources(rpc_configs),
         :ok <- verify_rpc_actions(rpc_configs, lookups),
         :ok <- verify_typed_queries(rpc_configs) do
      verify_relationship_read_actions(rpc_configs)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Cross-domain uniqueness of RPC action names / typed query names
  # ─────────────────────────────────────────────────────────────────

  defp verify_unique_names_across_domains(rpc_configs) do
    # Duplicate rpc_action names never get here: ash_rpc's decorator raises on
    # a duplicate wire entrypoint name while the manifest is built.
    typed_query_names =
      Enum.flat_map(rpc_configs, fn {_domain, resource_config} ->
        Enum.map(resource_config.typed_queries, & &1.name)
      end)

    case duplicates(typed_query_names) do
      [] ->
        :ok

      duplicate_queries ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate RPC typed queries found: #{inspect(duplicate_queries)}"
         )}
    end
  end

  defp duplicates(names) do
    names
    |> Enum.group_by(& &1)
    |> Enum.filter(fn {_, v} -> length(v) > 1 end)
    |> Enum.map(&elem(&1, 0))
  end

  # ─────────────────────────────────────────────────────────────────
  # Each rpc-listed resource must be an AshTypescript.Resource
  # ─────────────────────────────────────────────────────────────────

  defp verify_typescript_resources(rpc_configs) do
    Enum.reduce_while(rpc_configs, :ok, fn {_domain, resource_config}, acc ->
      resource = resource_config.resource

      cond do
        resource_config.rpc_actions == [] and resource_config.typed_queries == [] ->
          {:cont, acc}

        AshTypescript.Resource.Info.typescript_resource?(resource) ->
          {:cont, acc}

        true ->
          resource_label = resource |> to_string() |> String.trim_leading("Elixir.")

          {:halt,
           {:error,
            """
            #{resource_label} has rpc actions or typed queries, but is not properly configured for TypeScript generation.

            To fix this, ensure the resource:
            1. Has `AshTypescript.Resource` in its extensions list
            2. Has a `typescript` DSL block with at least `type_name` defined

            Example:
              use Ash.Resource,
                extensions: [AshTypescript.Resource]

              typescript do
                type_name "MyResource"
              end
            """}}
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Per-RPC-action validation: exists, public, options coherent
  # ─────────────────────────────────────────────────────────────────

  defp verify_rpc_actions(rpc_configs, lookups) do
    rpc_configs
    |> Enum.flat_map(fn {_domain, resource_config} ->
      resource = resource_config.resource
      Enum.map(resource_config.rpc_actions, &{resource, &1})
    end)
    |> Enum.reduce_while(:ok, fn {resource, rpc_action}, acc ->
      case verify_single_rpc_action(lookups, resource, rpc_action) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_single_rpc_action(lookups, resource, rpc_action) do
    case Ash.Resource.Info.action(resource, rpc_action.action) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "RPC action #{rpc_action.name} references action #{rpc_action.action}, which does not exist on resource #{inspect(resource)}"
         )}

      action ->
        with :ok <- verify_action_public(resource, rpc_action, action),
             :ok <- verify_read_action_public(resource, rpc_action),
             :ok <- verify_get_options(resource, rpc_action, action),
             :ok <- verify_show_metadata(resource, rpc_action, action) do
          verify_load_restrictions(lookups, resource, rpc_action)
        end
    end
  end

  defp verify_show_metadata(resource, rpc_action, action) do
    case Map.get(rpc_action, :show_metadata) do
      fields when is_list(fields) and fields != [] ->
        metadata_names = action |> Map.get(:metadata, []) |> Enum.map(& &1.name)
        invalid = Enum.reject(fields, &(&1 in metadata_names))

        if invalid == [] do
          :ok
        else
          {:error,
           Spark.Error.DslError.exception(
             message:
               "RPC action #{rpc_action.name}: show_metadata contains unknown metadata fields: #{inspect(invalid)}. " <>
                 "The action #{rpc_action.action} on #{inspect(resource)} defines metadata fields: #{inspect(metadata_names)}."
           )}
        end

      _ ->
        :ok
    end
  end

  defp verify_action_public(resource, rpc_action, action) do
    if Map.get(action, :public?, true) do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message:
           "RPC action #{rpc_action.name} references action #{action.name} on #{inspect(resource)}, which is not `public?`. " <>
             "Only `public?` actions can be used with AshTypescript RPC."
       )}
    end
  end

  defp verify_read_action_public(resource, rpc_action) do
    case Map.get(rpc_action, :read_action) do
      nil ->
        :ok

      read_action_name ->
        read_action = Ash.Resource.Info.action(resource, read_action_name)

        if read_action && !Map.get(read_action, :public?, true) do
          {:error,
           Spark.Error.DslError.exception(
             message:
               "RPC action #{rpc_action.name} references read_action #{read_action_name} on #{inspect(resource)}, which is not `public?`. " <>
                 "Only `public?` actions can be used with AshTypescript RPC."
           )}
        else
          :ok
        end
    end
  end

  defp verify_get_options(resource, rpc_action, action) do
    get? = Map.get(rpc_action, :get?, false)
    get_by = Map.get(rpc_action, :get_by) || []

    cond do
      get? and action.type != :read ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "RPC action #{rpc_action.name}: get? option can only be used on read actions, but #{rpc_action.action} is a #{action.type} action"
         )}

      get_by != [] and action.type != :read ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "RPC action #{rpc_action.name}: get_by option can only be used on read actions, but #{rpc_action.action} is a #{action.type} action"
         )}

      get? and get_by != [] ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "RPC action #{rpc_action.name}: get? and get_by options are mutually exclusive. Use get? to fetch by primary key, or get_by to fetch by specific fields."
         )}

      get_by != [] ->
        validate_get_by_fields_exist(resource, rpc_action, get_by)

      true ->
        :ok
    end
  end

  defp validate_get_by_fields_exist(resource, rpc_action, get_by) do
    invalid_fields =
      Enum.reject(get_by, fn field ->
        Ash.Resource.Info.attribute(resource, field) != nil
      end)

    if invalid_fields == [] do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message:
           "RPC action #{rpc_action.name}: get_by contains invalid fields: #{inspect(invalid_fields)}. These must be valid attribute names on the resource."
       )}
    end
  end

  defp verify_load_restrictions(lookups, resource, rpc_action) do
    allowed_loads = Map.get(rpc_action, :allowed_loads)
    denied_loads = Map.get(rpc_action, :denied_loads)

    cond do
      not is_nil(allowed_loads) and not is_nil(denied_loads) ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "RPC action #{rpc_action.name}: allowed_loads and denied_loads options are mutually exclusive. Use allowed_loads to restrict loading to specific fields, or denied_loads to block specific fields."
         )}

      not is_nil(allowed_loads) ->
        verify_load_paths(lookups, resource, rpc_action, :allowed_loads, allowed_loads)

      not is_nil(denied_loads) ->
        verify_load_paths(lookups, resource, rpc_action, :denied_loads, denied_loads)

      true ->
        :ok
    end
  end

  defp verify_load_paths({resource_lookup, type_lookup}, resource, rpc_action, option, loads) do
    case LoadPaths.invalid_paths(resource_lookup, type_lookup, resource, loads) do
      [] ->
        :ok

      invalid ->
        paths = Enum.map_join(invalid, "\n", &describe_invalid_path/1)

        {:error,
         Spark.Error.DslError.exception(
           message: """
           RPC action #{rpc_action.name}: #{option} contains invalid load paths:

           #{paths}

           Each entry must be a public relationship, calculation, aggregate,
           embedded-resource or union attribute reachable from #{inspect(resource)}.
           Only relationships, fields holding an embedded resource (attributes,
           calculations and aggregates), calculations returning a resource and
           unions have entries under them; a union's entries are its member
           names, and only members holding a resource have entries under them.
           """
         )}
    end
  end

  defp describe_invalid_path({path, resource, :unknown}),
    do:
      "  - #{Enum.join(path, ".")} (no loadable public field #{inspect(List.last(path))} " <>
        "on #{inspect(resource)})"

  defp describe_invalid_path({path, resource, :leaf}),
    do:
      "  - #{Enum.join(path, ".")} (#{inspect(List.last(path))} on #{inspect(resource)} " <>
        "has no fields to load under it)"

  defp describe_invalid_path({path, resource, :unknown_member}),
    do:
      "  - #{Enum.join(path, ".")} (no member #{inspect(List.last(path))} in the union " <>
        "#{inspect(union_name(path))} on #{inspect(resource)})"

  defp describe_invalid_path({path, resource, :scalar_member}),
    do:
      "  - #{Enum.join(path, ".")} (the member #{inspect(List.last(path))} of the union " <>
        "#{inspect(union_name(path))} on #{inspect(resource)} has no fields to load under it)"

  defp union_name(path), do: Enum.at(path, -2)

  # ─────────────────────────────────────────────────────────────────
  # Per-typed-query validation
  # ─────────────────────────────────────────────────────────────────

  defp verify_typed_queries(rpc_configs) do
    Enum.reduce_while(rpc_configs, :ok, fn {_domain, resource_config}, acc ->
      resource = resource_config.resource

      Enum.reduce_while(resource_config.typed_queries, acc, fn typed_query, _ ->
        case Ash.Resource.Info.action(resource, typed_query.action) do
          nil ->
            {:halt,
             {:error,
              Spark.Error.DslError.exception(
                message:
                  "Typed query #{typed_query.name} references action #{typed_query.action}, which does not exist on resource #{inspect(resource)}"
              )}}

          action ->
            if Map.get(action, :public?, true) do
              {:cont, :ok}
            else
              {:halt,
               {:error,
                Spark.Error.DslError.exception(
                  message:
                    "Typed query #{typed_query.name} references action #{action.name} on #{inspect(resource)}, which is not `public?`. " <>
                      "Only `public?` actions can be used with AshTypescript RPC."
                )}}
            end
        end
      end)
      |> case do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # ─────────────────────────────────────────────────────────────────
  # Relationship read actions on RPC resources must be public.
  # ─────────────────────────────────────────────────────────────────

  defp verify_relationship_read_actions(rpc_configs) do
    rpc_resources = rpc_configs |> Enum.map(fn {_d, rc} -> rc.resource end) |> Enum.uniq()

    Enum.reduce_while(rpc_resources, :ok, fn resource, acc ->
      case check_relationships(resource) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp check_relationships(resource) do
    resource
    |> Ash.Resource.Info.public_relationships()
    |> Enum.reduce_while(:ok, fn relationship, acc ->
      destination = relationship.destination

      with true <- AshTypescript.Resource.Info.typescript_resource?(destination),
           read_action when not is_nil(read_action) <- resolve_read_action(relationship),
           false <- Map.get(read_action, :public?, true) do
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message:
              "Relationship #{inspect(resource)}.#{relationship.name} points to #{inspect(destination)}, " <>
                "whose read action #{inspect(read_action.name)} is not `public?`. " <>
                "Public relationships on RPC resources must have `public?` read actions on their destination resources."
          )}}
      else
        _ -> {:cont, acc}
      end
    end)
  end

  defp resolve_read_action(relationship) do
    if relationship.read_action do
      Ash.Resource.Info.action(relationship.destination, relationship.read_action)
    else
      Ash.Resource.Info.primary_action(relationship.destination, :read)
    end
  end
end
