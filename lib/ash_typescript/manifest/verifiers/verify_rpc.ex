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
    * RPC action / typed query / argument names are TypeScript-safe.
    * Each public relationship's destination has a public read action.

  Also enforces cross-domain uniqueness of RPC action names and typed query names.

  Reads `rpc_configs` (raw per-resource RPC config including typed_queries) from
  the manifest module's persisted state so resources that are reachability roots
  without rpc_actions still get their typed_queries validated.
  """
  use Spark.Dsl.Verifier
  import AshTypescript.NameValidation, only: [invalid_name?: 1, make_name_better: 1]
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    manifest = Verifier.get_persisted(dsl, :manifest)
    resource_lookup = Verifier.get_persisted(dsl, :resource_lookup)
    rpc_configs = Verifier.get_persisted(dsl, :rpc_configs) || []
    do_verify(manifest, resource_lookup, rpc_configs)
  end

  defp do_verify(nil, _resource_lookup, _rpc_configs), do: :ok

  defp do_verify(%Ash.Info.Manifest{} = _manifest, _resource_lookup, rpc_configs) do
    with :ok <- verify_unique_names_across_domains(rpc_configs),
         :ok <- verify_typescript_resources(rpc_configs),
         :ok <- verify_rpc_actions(rpc_configs),
         :ok <- verify_typed_queries(rpc_configs),
         :ok <- verify_relationship_read_actions(rpc_configs) do
      verify_names(rpc_configs)
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
             :ok <- verify_get_options(resource, rpc_action, action) do
          verify_load_restrictions(rpc_action)
        end
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

  defp verify_load_restrictions(rpc_action) do
    allowed_loads = Map.get(rpc_action, :allowed_loads)
    denied_loads = Map.get(rpc_action, :denied_loads)

    if not is_nil(allowed_loads) and not is_nil(denied_loads) do
      {:error,
       Spark.Error.DslError.exception(
         message:
           "RPC action #{rpc_action.name}: allowed_loads and denied_loads options are mutually exclusive. Use allowed_loads to restrict loading to specific fields, or denied_loads to block specific fields."
       )}
    else
      :ok
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

  # ─────────────────────────────────────────────────────────────────
  # Name validation (rpc_action names, typed_query names, argument
  # / accept-attribute mapped names)
  # ─────────────────────────────────────────────────────────────────

  defp verify_names(rpc_configs) do
    errors =
      Enum.reduce(rpc_configs, [], fn {_domain, resource_config}, acc ->
        acc
        |> collect_invalid_rpc_action_names(resource_config.rpc_actions)
        |> collect_invalid_typed_query_names(resource_config.typed_queries)
        |> collect_invalid_action_arguments(resource_config)
      end)

    case errors do
      [] -> :ok
      _ -> format_name_validation_errors(Enum.reverse(errors))
    end
  end

  defp collect_invalid_rpc_action_names(errors, rpc_actions) do
    invalid =
      rpc_actions
      |> Enum.filter(&invalid_name?(&1.name))
      |> Enum.map(fn action -> {action.name, make_name_better(action.name)} end)

    if invalid == [], do: errors, else: [{:invalid_rpc_action_names, invalid} | errors]
  end

  defp collect_invalid_typed_query_names(errors, typed_queries) do
    invalid =
      typed_queries
      |> Enum.filter(&invalid_name?(&1.name))
      |> Enum.map(fn query -> {query.name, make_name_better(query.name)} end)

    if invalid == [], do: errors, else: [{:invalid_typed_query_names, invalid} | errors]
  end

  defp collect_invalid_action_arguments(errors, %{resource: resource} = resource_config) do
    invalid_args = collect_rpc_action_argument_errors(resource, resource_config.rpc_actions)
    invalid_tq_args = collect_typed_query_argument_errors(resource, resource_config.typed_queries)

    case invalid_args ++ invalid_tq_args do
      [] -> errors
      list -> [{:invalid_action_arguments, list} | errors]
    end
  end

  defp collect_rpc_action_argument_errors(resource, rpc_actions) do
    Enum.flat_map(rpc_actions, fn rpc_action ->
      case Ash.Resource.Info.action(resource, rpc_action.action) do
        nil ->
          []

        action ->
          argument_errors =
            action.arguments
            |> Enum.filter(fn arg ->
              arg.public? and
                invalid_name?(
                  AshTypescript.Resource.Info.get_mapped_argument_name(
                    resource,
                    rpc_action.action,
                    arg.name
                  )
                )
            end)
            |> Enum.map(fn arg ->
              {rpc_action.name, rpc_action.action, :argument, arg.name,
               make_name_better(arg.name)}
            end)

          accept_errors =
            case Map.get(action, :accept) do
              nil ->
                []

              accept_list ->
                accept_list
                |> Enum.filter(fn attr_name ->
                  mapped = AshTypescript.Resource.Info.get_mapped_field_name(resource, attr_name)
                  invalid_name?(mapped)
                end)
                |> Enum.map(fn attr_name ->
                  {rpc_action.name, rpc_action.action, :accepted_attribute, attr_name,
                   make_name_better(attr_name)}
                end)
            end

          argument_errors ++ accept_errors
      end
    end)
  end

  defp collect_typed_query_argument_errors(resource, typed_queries) do
    Enum.flat_map(typed_queries, fn typed_query ->
      case Ash.Resource.Info.action(resource, typed_query.action) do
        nil ->
          []

        action ->
          action.arguments
          |> Enum.filter(fn arg ->
            arg.public? and
              if AshTypescript.Resource.Info.typescript_resource?(resource) do
                invalid_name?(
                  AshTypescript.Resource.Info.get_mapped_argument_name(
                    resource,
                    typed_query.action,
                    arg.name
                  )
                )
              else
                invalid_name?(arg.name)
              end
          end)
          |> Enum.map(fn arg ->
            {typed_query.name, typed_query.action, :argument, arg.name,
             make_name_better(arg.name)}
          end)
      end
    end)
  end

  defp format_name_validation_errors(errors) do
    message_parts = Enum.map_join(errors, "\n\n", &format_error_part/1)

    {:error,
     Spark.Error.DslError.exception(
       message: """
       Invalid names found that contain question marks, or numbers preceded by underscores.
       These patterns are not allowed in TypeScript generation.

       #{message_parts}

       Names should use standard camelCase or snake_case patterns without numbered suffixes.
       """
     )}
  end

  defp format_error_part({:invalid_rpc_action_names, actions}) do
    suggestions =
      Enum.map_join(actions, "\n", fn {current, suggested} ->
        "  - #{current} → #{suggested}"
      end)

    "Invalid RPC action names:\n#{suggestions}"
  end

  defp format_error_part({:invalid_typed_query_names, queries}) do
    suggestions =
      Enum.map_join(queries, "\n", fn {current, suggested} ->
        "  - #{current} → #{suggested}"
      end)

    "Invalid typed query names:\n#{suggestions}"
  end

  defp format_error_part({:invalid_action_arguments, arguments}) do
    suggestions =
      Enum.map_join(arguments, "\n", fn {rpc_name, action_name, type, current, suggested} ->
        "  - #{rpc_name} (action #{action_name}) #{type} #{current} → #{suggested}"
      end)

    "Invalid action argument names:\n#{suggestions}"
  end
end
