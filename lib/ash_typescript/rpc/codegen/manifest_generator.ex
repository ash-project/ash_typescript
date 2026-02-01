# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Codegen.ManifestGenerator do
  @moduledoc """
  Generates a Markdown manifest of all RPC actions for discoverability.

  The manifest provides an overview of all available RPC functions, their types,
  and associated TypeScript artifacts (validation functions, Zod schemas, channel functions).

  Supports grouping by namespace when namespaces are configured, and includes
  detailed information like descriptions, deprecation notices, and related action references.
  """

  alias AshTypescript.Helpers
  alias AshTypescript.Rpc.Codegen.RpcConfigCollector

  @doc """
  Generates a Markdown manifest of all RPC actions for the given OTP application.

  Returns a string containing the complete manifest in Markdown format.

  ## Options
  The manifest respects the following configuration:
  - `add_ash_internals_to_manifest` - When true, includes Elixir module paths and internal action names
  """
  def generate_manifest(otp_app) do
    include_internals? = AshTypescript.Rpc.add_ash_internals_to_manifest?()

    # Get namespaced actions to determine if we should group by namespace
    namespaced_actions = RpcConfigCollector.get_rpc_resources_by_namespace(otp_app)
    has_namespaces? = has_meaningful_namespaces?(namespaced_actions)

    date = Date.utc_today() |> Date.to_string()

    content =
      if has_namespaces? do
        generate_namespace_grouped_content(namespaced_actions, include_internals?)
      else
        generate_domain_grouped_content(otp_app, include_internals?)
      end

    """
    # RPC Action Manifest

    Generated: #{date}

    #{content}
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  # Check if there are any actual namespaces configured (not just nil)
  defp has_meaningful_namespaces?(namespaced_actions) do
    namespaced_actions
    |> Map.keys()
    |> Enum.any?(&(&1 != nil))
  end

  # Generate content grouped by namespace
  defp generate_namespace_grouped_content(namespaced_actions, include_internals?) do
    # Sort namespaces: nil first (as "Default"), then alphabetically
    sorted_namespaces =
      namespaced_actions
      |> Map.keys()
      |> Enum.sort_by(fn
        nil -> {0, ""}
        ns -> {1, ns}
      end)

    sorted_namespaces
    |> Enum.map_join("\n", fn namespace ->
      actions = namespaced_actions[namespace]
      generate_namespace_section(namespace, actions, include_internals?)
    end)
  end

  defp generate_namespace_section(namespace, actions, include_internals?) do
    section_title =
      case namespace do
        nil -> "Default (No Namespace)"
        ns -> "Namespace: #{ns}"
      end

    # Group actions by resource for better organization within namespace
    actions_by_resource =
      actions
      |> Enum.group_by(fn {resource, _action, _rpc_action, _domain, _resource_config} ->
        resource
      end)
      |> Enum.sort_by(fn {resource, _} -> resource_short_name(resource) end)

    resource_sections =
      actions_by_resource
      |> Enum.map_join("\n", fn {resource, resource_actions} ->
        generate_resource_actions_section(resource, resource_actions, include_internals?)
      end)

    """
    ## #{section_title}

    #{resource_sections}
    """
  end

  defp generate_resource_actions_section(resource, actions, include_internals?) do
    resource_name = resource_short_name(resource)

    sorted_actions =
      actions
      |> Enum.sort_by(fn {_resource, _action, rpc_action, _domain, _resource_config} ->
        Atom.to_string(rpc_action.name)
      end)

    table = generate_actions_table_from_tuples(sorted_actions, include_internals?)

    # Get typed queries for this resource from any of the resource configs
    typed_queries =
      actions
      |> Enum.flat_map(fn {_resource, _action, _rpc_action, _domain, resource_config} ->
        Map.get(resource_config, :typed_queries, [])
      end)
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(fn typed_query -> Atom.to_string(typed_query.name) end)

    typed_queries_section = generate_typed_queries_section(typed_queries)

    """
    ### #{resource_name}

    #{table}
    #{typed_queries_section}
    """
    |> String.trim_trailing()
  end

  # Generate content grouped by domain (original behavior)
  defp generate_domain_grouped_content(otp_app, include_internals?) do
    domain_configs = RpcConfigCollector.get_rpc_config_by_domain(otp_app)

    sorted_domains =
      domain_configs
      |> Enum.sort_by(fn {domain, _config} -> inspect(domain) end)

    sorted_domains
    |> Enum.map_join("\n", fn {domain, rpc_config} ->
      generate_domain_section(domain, rpc_config, include_internals?)
    end)
  end

  defp generate_domain_section(domain, rpc_config, include_internals?) do
    domain_name = inspect(domain)

    # Filter to only resources with RPC actions, then sort alphabetically
    sorted_resources =
      rpc_config
      |> Enum.filter(fn %{rpc_actions: rpc_actions} -> rpc_actions != [] end)
      |> Enum.sort_by(fn %{resource: resource} -> resource_short_name(resource) end)

    resource_sections =
      sorted_resources
      |> Enum.map_join("\n", fn resource_config ->
        generate_resource_section(domain, resource_config, include_internals?)
      end)

    """
    ## #{domain_name}

    #{resource_sections}
    """
  end

  defp generate_resource_section(
         domain,
         %{
           resource: resource,
           rpc_actions: rpc_actions,
           typed_queries: typed_queries
         } = resource_config,
         include_internals?
       ) do
    resource_name = resource_short_name(resource)

    sorted_actions =
      rpc_actions
      |> Enum.sort_by(fn rpc_action -> Atom.to_string(rpc_action.name) end)

    sorted_typed_queries =
      typed_queries
      |> Enum.sort_by(fn typed_query -> Atom.to_string(typed_query.name) end)

    actions_table =
      generate_actions_table(
        resource,
        sorted_actions,
        domain,
        resource_config,
        include_internals?
      )

    typed_queries_section = generate_typed_queries_section(sorted_typed_queries)

    """
    ### #{resource_name}

    #{actions_table}
    #{typed_queries_section}
    """
    |> String.trim_trailing()
  end

  defp generate_actions_table(resource, rpc_actions, domain, resource_config, include_internals?) do
    show_validation = AshTypescript.Rpc.generate_validation_functions?()
    show_zod = AshTypescript.Rpc.generate_zod_schemas?()
    show_channel = AshTypescript.Rpc.generate_phx_channel_rpc_actions?()

    headers = build_headers(show_validation, show_zod, show_channel, include_internals?)
    separator = build_separator(show_validation, show_zod, show_channel, include_internals?)

    rows =
      rpc_actions
      |> Enum.map_join("\n", fn rpc_action ->
        action = Ash.Resource.Info.action(resource, rpc_action.action)
        namespace = RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action)

        build_row(
          resource,
          action,
          rpc_action,
          namespace,
          show_validation,
          show_zod,
          show_channel,
          include_internals?
        )
      end)

    details =
      rpc_actions
      |> Enum.map(fn rpc_action ->
        action = Ash.Resource.Info.action(resource, rpc_action.action)
        namespace = RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action)
        build_action_details(resource, action, rpc_action, namespace, include_internals?)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    table = """
    #{headers}
    #{separator}
    #{rows}
    """

    if details != "" do
      table <> "\n" <> details
    else
      table
    end
  end

  defp generate_actions_table_from_tuples(actions, include_internals?) do
    show_validation = AshTypescript.Rpc.generate_validation_functions?()
    show_zod = AshTypescript.Rpc.generate_zod_schemas?()
    show_channel = AshTypescript.Rpc.generate_phx_channel_rpc_actions?()

    headers = build_headers(show_validation, show_zod, show_channel, include_internals?)
    separator = build_separator(show_validation, show_zod, show_channel, include_internals?)

    rows =
      actions
      |> Enum.map_join("\n", fn {resource, action, rpc_action, domain, resource_config} ->
        namespace = RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action)

        build_row(
          resource,
          action,
          rpc_action,
          namespace,
          show_validation,
          show_zod,
          show_channel,
          include_internals?
        )
      end)

    details =
      actions
      |> Enum.map(fn {resource, action, rpc_action, domain, resource_config} ->
        namespace = RpcConfigCollector.resolve_namespace(domain, resource_config, rpc_action)
        build_action_details(resource, action, rpc_action, namespace, include_internals?)
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    table = """
    #{headers}
    #{separator}
    #{rows}
    """

    if details != "" do
      table <> "\n" <> details
    else
      table
    end
  end

  defp build_headers(show_validation, show_zod, show_channel, include_internals?) do
    base = "| Function | Action Type |"

    base
    |> maybe_append(" Ash Action |", include_internals?)
    |> maybe_append(" Resource |", include_internals?)
    |> maybe_append(" Validation |", show_validation)
    |> maybe_append(" Zod Schema |", show_zod)
    |> maybe_append(" Channel |", show_channel)
  end

  defp build_separator(show_validation, show_zod, show_channel, include_internals?) do
    base = "|----------|-------------|"

    base
    |> maybe_append("------------|", include_internals?)
    |> maybe_append("----------|", include_internals?)
    |> maybe_append("------------|", show_validation)
    |> maybe_append("------------|", show_zod)
    |> maybe_append("---------|", show_channel)
  end

  defp build_row(
         resource,
         action,
         rpc_action,
         _namespace,
         show_validation,
         show_zod,
         show_channel,
         include_internals?
       ) do
    function_name = Helpers.snake_to_camel_case(rpc_action.name)
    action_type = Atom.to_string(action.type)
    action_name = Atom.to_string(rpc_action.action)
    resource_module = inspect(resource)

    base = "| `#{function_name}` | #{action_type} |"

    base
    |> maybe_append(" `#{action_name}` |", include_internals?)
    |> maybe_append(" `#{resource_module}` |", include_internals?)
    |> maybe_append(
      " `validate#{Helpers.snake_to_pascal_case(rpc_action.name)}` |",
      show_validation
    )
    |> maybe_append(" `#{Helpers.snake_to_pascal_case(rpc_action.name)}InputSchema` |", show_zod)
    |> maybe_append(" `#{function_name}Channel` |", show_channel)
  end

  defp build_action_details(resource, action, rpc_action, namespace, include_internals?) do
    function_name = Helpers.snake_to_camel_case(rpc_action.name)
    resource_name = resource |> Module.split() |> List.last()

    description = get_description(rpc_action, action, resource_name, include_internals?)
    deprecated = get_deprecated_text(rpc_action)
    see_refs = get_see_refs(rpc_action)
    namespace_text = if namespace, do: "**Namespace:** `#{namespace}`", else: nil

    details =
      [description, deprecated, see_refs, namespace_text]
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(details) do
      nil
    else
      details_text = Enum.join(details, " | ")
      "- **`#{function_name}`**: #{details_text}"
    end
  end

  defp get_description(rpc_action, action, resource_name, include_internals?) do
    rpc_description = Map.get(rpc_action, :description)
    action_description = Map.get(action, :description)

    cond do
      is_binary(rpc_description) and rpc_description != "" ->
        rpc_description

      include_internals? and is_binary(action_description) and action_description != "" ->
        action_description

      true ->
        default_description(action.type, resource_name)
    end
  end

  defp get_deprecated_text(rpc_action) do
    case Map.get(rpc_action, :deprecated) do
      nil -> nil
      false -> nil
      true -> "⚠️ **Deprecated**"
      message when is_binary(message) -> "⚠️ **Deprecated:** #{message}"
    end
  end

  defp get_see_refs(rpc_action) do
    see_list = Map.get(rpc_action, :see) || []

    if Enum.empty?(see_list) do
      nil
    else
      refs =
        Enum.map_join(see_list, ", ", fn action_name ->
          function_name = action_name |> Atom.to_string() |> Macro.camelize() |> decapitalize()
          "`#{function_name}`"
        end)

      "**See also:** #{refs}"
    end
  end

  defp decapitalize(<<first::utf8, rest::binary>>), do: String.downcase(<<first::utf8>>) <> rest
  defp decapitalize(""), do: ""

  defp default_description(:read, resource_name), do: "Read #{resource_name} records"
  defp default_description(:create, resource_name), do: "Create a new #{resource_name}"
  defp default_description(:update, resource_name), do: "Update an existing #{resource_name}"
  defp default_description(:destroy, resource_name), do: "Delete a #{resource_name}"

  defp default_description(:action, resource_name),
    do: "Execute generic action on #{resource_name}"

  defp maybe_append(string, suffix, true), do: string <> suffix
  defp maybe_append(string, _suffix, false), do: string

  defp generate_typed_queries_section([]), do: ""

  defp generate_typed_queries_section(typed_queries) do
    items =
      typed_queries
      |> Enum.map_join("\n", fn typed_query ->
        const_name =
          typed_query.ts_fields_const_name || Helpers.snake_to_camel_case(typed_query.name)

        type_name =
          typed_query.ts_result_type_name ||
            "#{Helpers.snake_to_pascal_case(typed_query.name)}Result"

        description = Map.get(typed_query, :description)

        if is_binary(description) and description != "" do
          "- `#{const_name}` → `#{type_name}`: #{description}"
        else
          "- `#{const_name}` → `#{type_name}`"
        end
      end)

    """

    **Typed Queries:**
    #{items}
    """
  end

  defp resource_short_name(resource) do
    resource
    |> Module.split()
    |> List.last()
  end
end
