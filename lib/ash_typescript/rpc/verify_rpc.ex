defmodule AshTypescript.Rpc.VerifyRpc do
  @moduledoc """
  Checks that all RPC actions and typed queries reference existing resource actions.
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
               :ok <- verify_typed_queries(resource, typed_queries) do
            {:cont, acc}
          else
            false ->
              resource = resource |> to_string() |> String.trim("Elixir.")

              {:halt,
               {:error,
                "#{resource} has rpc actions or typed queries, but is not using the AshTypescript.Resource extension"}}

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
end
