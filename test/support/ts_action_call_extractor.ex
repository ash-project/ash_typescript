# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TsActionCallExtractor do
  @moduledoc """
  Extracts RPC action calls from TypeScript test files.

  Parses function calls in the format `await functionName({...});` and converts
  them to Elixir test data that can be used to generate runtime validation tests.

  ## Expected Format

  The TypeScript files must follow this strict format:

      await createTodo({
        input: {title: "Test"},
        fields: ["id"]
      });

  ## Example

      iex> extract_calls(~S'''
      ...> await createTodo({
      ...>   input: {title: "Test"},
      ...>   fields: ["id"]
      ...> });
      ...> ''')
      [%{
        function_name: "createTodo",
        action_name: "create_todo",
        config: %{"input" => %{"title" => "Test"}, "fields" => ["id"]}
      }]
  """

  @doc """
  Extract all RPC calls from a TypeScript file or content string.

  Returns a list of maps containing:
  - `:function_name` - The camelCase function name from TypeScript
  - `:action_name` - The snake_case action name for Elixir
  - `:config` - The parsed configuration map
  """
  def extract_calls(content) when is_binary(content) do
    # Pattern: await functionName({...});
    # We need to find the function name and then extract content until ");",
    # accounting for nested parentheses
    pattern = ~r/await\s+(\w+)\(/

    pattern
    |> Regex.scan(content, capture: :all, return: :index)
    |> Enum.map(fn [{match_start, match_len}, {func_start, func_len}] ->
      function_name = String.slice(content, func_start, func_len)

      # Position right after the opening parenthesis
      start_pos = match_start + match_len

      # Extract until we find ");" accounting for nesting
      case extract_until_closing(content, start_pos) do
        {:ok, arg_string} ->
          action_name = AshTypescript.Helpers.camel_to_snake_case(function_name)

          case ts_to_map(arg_string) do
            {:ok, config} ->
              %{
                function_name: function_name,
                action_name: action_name,
                config: config
              }

            {:error, _reason} ->
              nil
          end

        {:error, _reason} ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Extract content from start_pos until we find ");" at the correct nesting level
  defp extract_until_closing(content, start_pos) do
    extract_until_closing_recursive(content, start_pos, 0, false, false, "")
  end

  defp extract_until_closing_recursive(content, pos, depth, in_string, escaped, acc) do
    case String.at(content, pos) do
      nil ->
        {:error, :no_closing}

      "\\" when in_string ->
        extract_until_closing_recursive(
          content,
          pos + 1,
          depth,
          in_string,
          not escaped,
          acc <> "\\"
        )

      "\"" when not escaped ->
        extract_until_closing_recursive(
          content,
          pos + 1,
          depth,
          not in_string,
          false,
          acc <> "\""
        )

      "(" when not in_string ->
        extract_until_closing_recursive(content, pos + 1, depth + 1, in_string, false, acc <> "(")

      ")" when not in_string ->
        if depth == 0 do
          # Check if we're followed by optional whitespace and then ";"
          # Look ahead to find ";" after any whitespace
          check_pos = pos + 1
          check_result = check_for_semicolon(content, check_pos)

          if check_result do
            {:ok, acc}
          else
            # Not the final closing, continue
            extract_until_closing_recursive(content, pos + 1, depth, in_string, false, acc <> ")")
          end
        else
          extract_until_closing_recursive(
            content,
            pos + 1,
            depth - 1,
            in_string,
            false,
            acc <> ")"
          )
        end

      char ->
        extract_until_closing_recursive(content, pos + 1, depth, in_string, false, acc <> char)
    end
  end

  # Check if a semicolon appears at or after the given position, skipping whitespace
  defp check_for_semicolon(content, pos) do
    case String.at(content, pos) do
      nil -> false
      ";" -> true
      char when char in [" ", "\t", "\n", "\r"] -> check_for_semicolon(content, pos + 1)
      _ -> false
    end
  end

  # Convert TypeScript object literal to Elixir map.
  #
  # Performs the following transformations:
  # 1. Remove comments (// and /* */)
  # 2. Remove trailing commas
  # 3. Quote unquoted object keys
  # 4. Replace undefined with null
  # 5. Remove TypeScript-specific syntax (as const)
  # 6. Parse as JSON
  defp ts_to_map(ts_string) do
    try do
      json_string =
        ts_string
        |> remove_comments()
        |> remove_trailing_commas()
        |> quote_object_keys()
        |> String.replace("undefined", "null")
        |> remove_as_const()

      with {:error, reason} <- Jason.decode(json_string) do
        {:error, {:json_parse_error, reason}}
      end
    rescue
      e -> {:error, {:exception, e}}
    end
  end

  # Remove JavaScript/TypeScript comments.
  #
  # Handles both single-line (//) and multi-line (/* */) comments.
  defp remove_comments(string) do
    string
    # Remove multi-line comments first (they can span multiple lines)
    |> String.replace(~r/\/\*.*?\*\//s, "")
    # Remove single-line comments (from // to end of line)
    |> String.replace(~r/\/\/.*$/m, "")
  end

  # Remove trailing commas before closing braces or brackets.
  #
  # Examples:
  # - {a: 1,} -> {a: 1}
  # - [1, 2,] -> [1, 2]
  defp remove_trailing_commas(string) do
    string
    |> String.replace(~r/,(\s*[}\]])/, "\\1")
  end

  # Quote unquoted object keys while preserving strings.
  #
  # Uses a state machine to track whether we're inside a string literal,
  # and only quotes keys when outside of strings.
  #
  # Examples:
  # - {input: {...}} -> {"input": {...}}
  # - {title: "value: with colon"} -> {"title": "value: with colon"}
  defp quote_object_keys(string) do
    quote_object_keys_recursive(string, "", false, false)
  end

  defp quote_object_keys_recursive("", acc, _in_string, _escaped) do
    acc
  end

  defp quote_object_keys_recursive(<<"\\"::binary, rest::binary>>, acc, true, _escaped) do
    # Escape character inside string
    quote_object_keys_recursive(rest, acc <> "\\", true, true)
  end

  defp quote_object_keys_recursive(<<"\""::binary, rest::binary>>, acc, in_string, false) do
    # Quote - toggle string state if not escaped
    quote_object_keys_recursive(rest, acc <> "\"", not in_string, false)
  end

  defp quote_object_keys_recursive(string, acc, false, _escaped) do
    # Outside string - look for unquoted keys (word followed by colon)
    case Regex.run(~r/^(\s*)(\w+)(\s*):/, string) do
      [match, ws1, key, ws2] ->
        # Found an unquoted key
        rest = String.slice(string, String.length(match)..-1//1)
        quoted = "#{ws1}\"#{key}\"#{ws2}:"
        quote_object_keys_recursive(rest, acc <> quoted, false, false)

      nil ->
        # No unquoted key - take first character and continue
        <<char::binary-size(1), rest::binary>> = string
        quote_object_keys_recursive(rest, acc <> char, false, false)
    end
  end

  defp quote_object_keys_recursive(
         <<char::binary-size(1), rest::binary>>,
         acc,
         in_string,
         _escaped
       ) do
    # Inside string or after processing escape - just append character
    quote_object_keys_recursive(rest, acc <> char, in_string, false)
  end

  # Remove TypeScript 'as const' assertions.
  #
  # Example: ["id", "title"] as const -> ["id", "title"]
  defp remove_as_const(string) do
    string
    |> String.replace(~r/\s+as\s+const/, "")
  end
end
