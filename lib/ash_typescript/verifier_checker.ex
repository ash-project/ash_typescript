# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.VerifierChecker do
  @moduledoc """
  Re-runs per-module Spark verifiers for the AshTypescript Resource, Rpc,
  TypedController and TypedChannel extensions. Spark emits warnings (rather
  than raising) when a verifier fails; during codegen we want to promote those
  warnings to hard errors. This module iterates the configured verifiers for
  each module and aggregates failures.

  Manifest-level verifiers are *not* run here — they're a property of the
  `AshTypescript.Manifest` module and are checked at compile time by Spark, and
  re-checked at codegen time via `AshTypescript.Manifest.run_verifiers/1` (or
  `verify_for_domains/2` for inline test manifests). Generated names are
  checked while the manifest module compiles (`AshTypescript.Manifest.NameCheck`).
  """

  @doc """
  Checks per-module AshTypescript extension verifiers for a list of modules.
  Returns `:ok` or `{:error, formatted_message}`.
  """
  def check_all_verifiers(modules) do
    case Enum.flat_map(modules, &check_module_verifiers/1) do
      [] -> :ok
      errors -> {:error, format_verifier_errors(errors)}
    end
  end

  defp check_module_verifiers(module) do
    extensions = Spark.extensions(module)
    dsl_config = module.spark_dsl_config()

    ash_typescript_extensions = [
      AshTypescript.Resource,
      AshTypescript.Rpc,
      AshTypescript.TypedController.Dsl,
      AshTypescript.TypedChannel.Dsl
    ]

    extensions
    |> Enum.filter(&(&1 in ash_typescript_extensions))
    |> Enum.flat_map(fn extension ->
      Code.ensure_loaded!(extension)

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
    verifier
    |> run_verifier(dsl_config)
    |> Enum.map(&{module, verifier, &1})
  end

  @doc false
  # Runs one Spark verifier against `dsl` and returns its errors: none for
  # `:ok`, each warning (Spark only prints them at compile time), the error,
  # or the exception the verifier raised. `AshTypescript.Manifest` runs its
  # verifiers through this too.
  @spec run_verifier(module(), term()) :: [term()]
  def run_verifier(verifier, dsl) do
    case verifier.verify(dsl) do
      :ok -> []
      {:warn, warnings} -> List.wrap(warnings)
      {:error, error} -> [error]
    end
  rescue
    e -> [e]
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

  @doc false
  # The message of an error `run_verifier/2` returned.
  @spec format_error(term()) :: String.t()
  def format_error(%Spark.Error.DslError{message: message}), do: message
  def format_error(error) when is_binary(error), do: error
  def format_error(error), do: Exception.message(error)
end
