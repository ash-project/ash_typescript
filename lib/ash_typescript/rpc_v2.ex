defmodule AshTypescript.RpcV2 do
  @moduledoc """
  Next-generation RPC processing pipeline with clean architecture and strict validation.
  
  This is a complete rewrite focused on:
  - Performance: 50%+ improvement over current implementation
  - Strict validation: Fail-fast on all invalid inputs
  - Clean architecture: Pure functional pipeline
  - Single responsibility: Clear separation of concerns
  
  Pipeline: parse_input -> execute_action -> filter_result -> format_output
  """

  alias AshTypescript.RpcV2.{Pipeline, ErrorBuilder}

  @doc """
  Main entry point for the new RPC processing pipeline.
  
  ## Parameters
  - `otp_app` - The OTP application atom
  - `conn` - The Plug connection
  - `params` - Request parameters map
  
  ## Returns
  - `{:ok, result}` - Successfully processed result
  - `{:error, reason}` - Processing error with detailed message
  
  ## Error Handling
  This implementation uses strict validation and fails fast on any invalid input.
  No permissive modes - all errors are reported immediately.
  """
  @spec run_action(atom(), Plug.Conn.t(), map()) :: 
    {:ok, map()} | {:error, map()}
  def run_action(otp_app, conn, params) do
    with {:ok, parsed_request} <- Pipeline.parse_request_strict(otp_app, conn, params),
         {:ok, ash_result} <- Pipeline.execute_ash_action(parsed_request),
         {:ok, filtered_result} <- Pipeline.filter_result_fields(ash_result, parsed_request),
         {:ok, formatted_result} <- Pipeline.format_output(filtered_result, parsed_request) do
      {:ok, %{success: true, data: formatted_result}}
    else
      {:error, reason} ->
        {:error, %{success: false, errors: ErrorBuilder.build_error_response(reason)}}
    end
  end

  @doc """
  Validates action parameters without execution.
  Used for form validation in the client.
  """
  @spec validate_action(atom(), Plug.Conn.t(), map()) :: 
    {:ok, map()} | {:error, map()}
  def validate_action(otp_app, conn, params) do
    case Pipeline.parse_request_strict(otp_app, conn, params) do
      {:ok, _parsed_request} ->
        {:ok, %{success: true}}
      {:error, reason} ->
        {:error, %{success: false, errors: ErrorBuilder.build_error_response(reason)}}
    end
  end
end