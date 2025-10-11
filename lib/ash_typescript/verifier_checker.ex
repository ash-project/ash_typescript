defmodule AshTypescript.VerifierChecker do
  @moduledoc """
  Checks if any verifiers have failed for resources and domains.

  This is needed because Spark verifiers now emit warnings instead of errors,
  so we need to re-run them during codegen to detect issues.
  """

  @doc """
  Checks all verifiers for a list of modules (resources/domains).
  Returns :ok or {:error, formatted_message}
  """
  def check_all_verifiers(modules) do
    errors =
      modules
      |> Enum.flat_map(&check_module_verifiers/1)

    case errors do
      [] -> :ok
      errors -> {:error, format_verifier_errors(errors)}
    end
  end

  defp check_module_verifiers(module) do
    extensions = module.__info__(:attributes)[:extensions] || []
    dsl_config = module.spark_dsl_config()

    extensions
    |> Enum.flat_map(fn extension ->
      if function_exported?(extension, :verifiers, 0) do
        extension.verifiers()
      else
        []
      end
    end)
    |> Enum.flat_map(fn verifier ->
      check_single_verifier(module, verifier, dsl_config)
    end)
  end

  defp check_single_verifier(module, verifier, dsl_config) do
    try do
      case verifier.verify(dsl_config) do
        :ok ->
          []

        {:warn, warnings} ->
          warnings_list = List.wrap(warnings)

          Enum.map(warnings_list, fn warning ->
            {module, verifier, warning}
          end)

        {:error, error} ->
          [{module, verifier, error}]
      end
    rescue
      e -> [{module, verifier, e}]
    end
  end

  defp format_verifier_errors(errors) do
    errors
    |> Enum.map_join("\n\n", fn {module, verifier, error} ->
      """
      Module: #{inspect(module)}
      Verifier: #{inspect(verifier)}
      Error: #{format_error(error)}
      """
      |> String.trim()
    end)
  end

  defp format_error(%Spark.Error.DslError{message: message}), do: message
  defp format_error(error) when is_binary(error), do: error
  defp format_error(error), do: Exception.message(error)
end
