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
    * `:allowed_loads` / `:denied_loads` are mutually exclusive.
    * Each public relationship's destination has a public read action.

  Also enforces cross-domain uniqueness of RPC action names and typed query names.
  The names generated for RPC actions and typed queries, and every client name,
  are checked when the manifest compiles (`AshTypescript.Manifest.NameCheck`).

  Reads `rpc_configs` (raw per-resource RPC config including typed_queries) from
  the manifest module's persisted state so resources that are reachability roots
  without rpc_actions still get their typed_queries validated.
  """
  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    case Verifier.get_persisted(dsl, :manifest) do
      nil -> :ok
      %Ash.Info.Manifest{} -> do_verify(Verifier.get_persisted(dsl, :rpc_configs) || [])
    end
  end

  defp do_verify(rpc_configs) do
    with :ok <- verify_unique_names_across_domains(rpc_configs),
         :ok <- verify_typescript_resources(rpc_configs),
         :ok <- verify_rpc_actions(rpc_configs),
         :ok <- verify_typed_queries(rpc_configs) do
      verify_relationship_read_actions(rpc_configs)
    end
  end

  # ─────────────────────────────────────────────────────────────────
  # Cross-domain uniqueness of RPC action names / typed query names
  # ─────────────────────────────────────────────────────────────────

  defp verify_unique_names_across_domains(rpc_configs) do
    {rpc_action_names, typed_query_names} =
      Enum.reduce(rpc_configs, {[], []}, fn {_domain, resource_config}, {actions, queries} ->
        actions = actions ++ Enum.map(resource_config.rpc_actions, & &1.name)
        queries = queries ++ Enum.map(resource_config.typed_queries, & &1.name)
        {actions, queries}
      end)

    duplicate_actions = duplicates(rpc_action_names)
    duplicate_queries = duplicates(typed_query_names)

    case {duplicate_actions, duplicate_queries} do
      {[], []} ->
        :ok

      {[], _} ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate RPC typed queries found: #{inspect(duplicate_queries)}"
         )}

      {_, []} ->
        {:error,
         Spark.Error.DslError.exception(
           message: "Duplicate RPC actions found: #{inspect(duplicate_actions)}"
         )}

      {_, _} ->
        {:error,
         Spark.Error.DslError.exception(
           message: """
           Duplicate RPC typed queries found: #{inspect(duplicate_queries)}
           Duplicate RPC actions found: #{inspect(duplicate_actions)}
           """
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

  defp verify_rpc_actions(rpc_configs) do
    rpc_configs
    |> Enum.flat_map(fn {_domain, resource_config} ->
      resource = resource_config.resource
      Enum.map(resource_config.rpc_actions, &{resource, &1})
    end)
    |> Enum.reduce_while(:ok, fn {resource, rpc_action}, acc ->
      case verify_single_rpc_action(resource, rpc_action) do
        :ok -> {:cont, acc}
        error -> {:halt, error}
      end
    end)
  end

  defp verify_single_rpc_action(resource, rpc_action) do
    case Ash.Resource.Info.action(resource, rpc_action.action) do
      nil ->
        {:error,
         Spark.Error.DslError.exception(
           message:
             "RPC action #{rpc_action.name} references action #{rpc_action.action}, which does not exist on resource #{resource}"
         )}

      action ->
        with :ok <- verify_action_public(resource, rpc_action, action),
             :ok <- verify_read_action_public(resource, rpc_action),
             :ok <- verify_get_options(resource, rpc_action, action),
             :ok <- verify_show_metadata(resource, rpc_action, action) do
          verify_load_restrictions(resource, rpc_action)
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

  defp verify_load_restrictions(resource, rpc_action) do
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
        verify_load_paths(resource, rpc_action, :allowed_loads, allowed_loads)

      not is_nil(denied_loads) ->
        verify_load_paths(resource, rpc_action, :denied_loads, denied_loads)

      true ->
        :ok
    end
  end

  defp verify_load_paths(resource, rpc_action, option, loads) do
    case collect_invalid_load_paths(resource, List.wrap(loads), []) do
      [] ->
        :ok

      invalid ->
        paths =
          Enum.map_join(invalid, "\n", fn {path, res} ->
            "  - #{Enum.join(path, ".")} (no loadable public field #{inspect(List.last(path))} on #{inspect(res)})"
          end)

        {:error,
         Spark.Error.DslError.exception(
           message: """
           RPC action #{rpc_action.name}: #{option} contains invalid load paths:

           #{paths}

           Each entry must be a public relationship, calculation, aggregate, or
           embedded-resource attribute reachable from #{inspect(resource)}.
           """
         )}
    end
  end

  # Walks an allowed_loads/denied_loads list (atoms and `{field, nested}`
  # keywords), validating each name against the loadable public fields of the
  # resource at that level. Descends into relationship destinations, embedded
  # attributes, and instance-of-resource calculations; when the next resource
  # cannot be determined (e.g. a plain-map calculation), deeper entries are
  # skipped rather than flagged — this verifier only rejects names that are
  # definitely not loadable.
  defp collect_invalid_load_paths(resource, loads, path) do
    Enum.flat_map(loads, fn
      field when is_atom(field) ->
        check_load_field(resource, field, path, [])

      {field, nested} when is_atom(field) and is_list(nested) ->
        check_load_field(resource, field, path, nested)

      _other ->
        []
    end)
  end

  defp check_load_field(resource, field, path, nested) do
    full_path = path ++ [field]

    case load_destination(resource, field) do
      :invalid -> [{full_path, resource}]
      {:ok, nil} -> []
      {:ok, destination} -> collect_invalid_load_paths(destination, nested, full_path)
    end
  end

  # Returns {:ok, destination_resource} when the field is loadable and nesting
  # can be validated against a known resource, {:ok, nil} when the field is
  # loadable but the nested resource can't be determined, or :invalid.
  defp load_destination(resource, field) do
    cond do
      relationship = Ash.Resource.Info.public_relationship(resource, field) ->
        {:ok, relationship.destination}

      calculation = Ash.Resource.Info.public_calculation(resource, field) ->
        {:ok, instance_of_resource(calculation.type, calculation.constraints)}

      Ash.Resource.Info.public_aggregate(resource, field) ->
        {:ok, nil}

      attribute = Ash.Resource.Info.public_attribute(resource, field) ->
        case instance_of_resource(attribute.type, attribute.constraints) do
          nil -> :invalid
          destination -> {:ok, destination}
        end

      true ->
        :invalid
    end
  end

  defp instance_of_resource({:array, type}, constraints) do
    instance_of_resource(type, Keyword.get(constraints, :items, []))
  end

  defp instance_of_resource(type, constraints) do
    cond do
      not is_atom(type) ->
        nil

      Code.ensure_loaded?(type) and Ash.Type.embedded_type?(type) ->
        if Ash.Resource.Info.resource?(type), do: type, else: nil

      type == Ash.Type.Struct ->
        with instance when is_atom(instance) and not is_nil(instance) <-
               Keyword.get(constraints, :instance_of),
             true <- Code.ensure_loaded?(instance) and Ash.Resource.Info.resource?(instance) do
          instance
        else
          _ -> nil
        end

      true ->
        nil
    end
  end

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
                  "Typed query #{typed_query.name} references action #{typed_query.action}, which does not exist on resource #{resource}"
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
