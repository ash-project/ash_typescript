# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.VerifyRpc do
  @moduledoc """
  Checks that all RPC actions and typed queries reference existing resource actions,
  and validates that names don't contain invalid patterns.
  """
  use Spark.Dsl.Verifier
  alias Spark.Dsl.Verifier

  @impl true
  def verify(dsl) do
    case verify_unique_rpc_action_and_typed_query_names(dsl) do
      :ok ->
        dsl
        |> Verifier.get_entities([:typescript_rpc])
        |> Enum.reduce_while(:ok, fn %{
                                       resource: resource,
                                       rpc_actions: rpc_actions,
                                       typed_queries: typed_queries
                                     },
                                     acc ->
          with true <- AshTypescript.Resource.Info.typescript_resource?(resource),
               :ok <- verify_rpc_actions(resource, rpc_actions),
               :ok <- verify_typed_queries(resource, typed_queries),
               :ok <- verify_names(resource, rpc_actions, typed_queries) do
            {:cont, acc}
          else
            false ->
              resource = resource |> to_string() |> String.trim("Elixir.")

              {:halt,
               {:error,
                """
                #{resource} has rpc actions or typed queries, but is not properly configured for TypeScript generation.

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

            error ->
              {:halt, error}
          end
        end)

      error ->
        error
    end
  end

  def verify_unique_rpc_action_and_typed_query_names(dsl) do
    rpc_domains =
      Mix.Project.config()[:app]
      |> Ash.Info.domains()
      |> Enum.filter(&AshTypescript.Rpc.Info.typescript_rpc/1)

    case rpc_domains do
      [] ->
        :ok

      [first_domain_with_rpc | _] ->
        domain = dsl[:persist][:module]

        if first_domain_with_rpc != domain do
          :ok
        else
          all_names =
            Enum.reduce(rpc_domains, %{rpc_actions: [], typed_queries: []}, fn domain, acc ->
              rpc = AshTypescript.Rpc.Info.typescript_rpc(domain)

              Enum.reduce(rpc, acc, fn resource, acc ->
                rpc_action_names = Enum.map(resource.rpc_actions, & &1.name)
                typed_query_names = Enum.map(resource.typed_queries, & &1.name)

                %{
                  acc
                  | rpc_actions: acc.rpc_actions ++ rpc_action_names,
                    typed_queries: acc.typed_queries ++ typed_query_names
                }
              end)
            end)

          duplicate_actions =
            all_names.rpc_actions
            |> Enum.group_by(& &1)
            |> Enum.filter(fn {_, v} ->
              case v do
                [_name] -> false
                _ -> true
              end
            end)
            |> Enum.map(&elem(&1, 0))

          duplicate_queries =
            all_names.typed_queries
            |> Enum.group_by(& &1)
            |> Enum.filter(fn {_, v} ->
              case v do
                [_name] -> false
                _ -> true
              end
            end)
            |> Enum.map(&elem(&1, 0))

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
    end
  end

  def verify_rpc_actions(resource, rpc_actions) do
    Enum.reduce_while(rpc_actions, :ok, fn rpc_action, acc ->
      if Ash.Resource.Info.action(resource, rpc_action.action) do
        {:cont, acc}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message:
              "RPC action #{rpc_action.name} references action #{rpc_action.action}, which does not exist on resource #{resource}"
          )}}
      end
    end)
  end

  def verify_typed_queries(resource, typed_queries) do
    Enum.reduce_while(typed_queries, :ok, fn typed_query, acc ->
      if Ash.Resource.Info.action(resource, typed_query.action) do
        {:cont, acc}
      else
        {:halt,
         {:error,
          Spark.Error.DslError.exception(
            message:
              "Typed query #{typed_query.name} references action #{typed_query.action}, which does not exist on resource #{resource}"
          )}}
      end
    end)
  end

  # Name validation functions

  @doc false
  def invalid_name?(name) do
    Regex.match?(~r/_+\d|\?/, to_string(name))
  end

  @doc false
  def make_name_better(name) do
    name
    |> to_string()
    |> String.replace(~r/_+\d/, fn v ->
      String.trim_leading(v, "_")
    end)
    |> String.replace("?", "")
  end

  defp verify_names(resource, rpc_actions, typed_queries) do
    errors = []

    # Validate RPC action names
    errors = validate_rpc_action_names(rpc_actions, errors)

    # Validate typed query names
    errors = validate_typed_query_names(typed_queries, errors)

    # Validate action arguments for RPC actions and typed queries
    errors = validate_action_argument_names(resource, rpc_actions, typed_queries, errors)

    case errors do
      [] -> :ok
      _ -> format_name_validation_errors(errors)
    end
  end

  defp validate_rpc_action_names(rpc_actions, errors) do
    invalid_actions =
      rpc_actions
      |> Enum.filter(&invalid_name?(&1.name))
      |> Enum.map(fn action ->
        {action.name, make_name_better(action.name)}
      end)

    case invalid_actions do
      [] -> errors
      _ -> [{:invalid_rpc_action_names, invalid_actions} | errors]
    end
  end

  defp validate_typed_query_names(typed_queries, errors) do
    invalid_queries =
      typed_queries
      |> Enum.filter(&invalid_name?(&1.name))
      |> Enum.map(fn query ->
        {query.name, make_name_better(query.name)}
      end)

    case invalid_queries do
      [] -> errors
      _ -> [{:invalid_typed_query_names, invalid_queries} | errors]
    end
  end

  defp validate_action_argument_names(resource, rpc_actions, typed_queries, errors) do
    # Validate RPC action arguments
    rpc_action_arguments =
      rpc_actions
      |> Enum.flat_map(fn rpc_action ->
        action = Ash.Resource.Info.action(resource, rpc_action.action)

        if action do
          argument_errors =
            action.arguments
            |> Enum.filter(fn arg ->
              mapped_name =
                AshTypescript.Resource.Info.get_mapped_argument_name(
                  resource,
                  rpc_action.action,
                  arg.name
                )

              invalid_name?(mapped_name)
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
                  # Check if the mapped name is still invalid
                  mapped_name =
                    AshTypescript.Resource.Info.get_mapped_field_name(
                      resource,
                      attr_name
                    )

                  invalid_name?(mapped_name)
                end)
                |> Enum.map(fn attr_name ->
                  {rpc_action.name, rpc_action.action, :accepted_attribute, attr_name,
                   make_name_better(attr_name)}
                end)
            end

          argument_errors ++ accept_errors
        else
          []
        end
      end)

    # Validate typed query arguments
    typed_query_arguments =
      typed_queries
      |> Enum.flat_map(fn typed_query ->
        action = Ash.Resource.Info.action(resource, typed_query.action)

        if action do
          action.arguments
          |> Enum.filter(fn arg ->
            if AshTypescript.Resource.Info.typescript_resource?(resource) do
              # Check if the mapped name is still invalid
              mapped_name =
                AshTypescript.Resource.Info.get_mapped_argument_name(
                  resource,
                  typed_query.action,
                  arg.name
                )

              invalid_name?(mapped_name)
            else
              invalid_name?(arg.name)
            end
          end)
          |> Enum.map(fn arg ->
            {typed_query.name, typed_query.action, :argument, arg.name,
             make_name_better(arg.name)}
          end)
        else
          []
        end
      end)

    invalid_arguments = rpc_action_arguments ++ typed_query_arguments

    case invalid_arguments do
      [] -> errors
      _ -> [{:invalid_action_arguments, invalid_arguments} | errors]
    end
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
