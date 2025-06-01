defmodule Mix.Tasks.AshTypescript.Codegen do
  @moduledoc """
  Generates TypeScript types for Ash RPC-calls.

  Usage:
    mix ash_typescript.codegen --files "assets/js/ash_rpc/*.json, assets/list_users.json" --output "assets/js/ash_generated.ts"
  """

  @shortdoc "Generates TypeScript types for Ash RPC-calls"

  use Mix.Task
  alias AshTypescript.Helpers

  def run(args) do
    Mix.Task.run("compile")

    {opts, _remaining, _invalid} =
      OptionParser.parse(args,
        switches: [
          files: :string,
          output: :string,
          process_endpoint: :string,
          validate_endpoint: :string
        ],
        aliases: [f: :files, o: :string, p: :process_endpoint, v: :validate_endpoint]
      )

    otp_app = Mix.Project.config()[:app]

    pattern = Keyword.get(opts, :files, "assets/js/ash_rpc/*.json")
    output_file = Keyword.get(opts, :output, "assets/js/ash_rpc.ts")
    process_endpoint = Keyword.get(opts, :process_endpoint, "/rpc/run")
    validate_endpoint = Keyword.get(opts, :validate_endpoint, "/rpc/validate")

    endpoint_process_arg = "endpoint: string = \"#{process_endpoint}\""
    endpoint_validate_arg = "endpoint: string = \"#{validate_endpoint}\""
    patterns = String.split(pattern, ",", trim: true)
    files = Enum.flat_map(patterns, &Path.wildcard/1) |> Enum.uniq()

    if files == [] do
      raise "No files matched the pattern: #{pattern}"
    end

    resources_and_actions =
      otp_app
      |> Ash.Info.domains()
      |> Enum.flat_map(fn domain ->
        AshTypescript.RPC.Info.rpc(domain)
      end)

    load_type = """
    type AshLoadList = Array<string | { [key: string]: AshLoadList }>;

    function getCSRFToken(): string | null {
      const metaElement = document.querySelector('meta[name="csrf-token"]');
      return metaElement ? metaElement.getAttribute('content') : null;
    }
    """

    types =
      files
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> Jason.decode!()
        |> List.wrap()
      end)
      |> Enum.reduce(load_type, fn rpc_spec, content ->
        {resource, rpc_action} =
          Enum.find_value(resources_and_actions, fn %{
                                                      resource: resource,
                                                      rpc_actions: rpc_actions
                                                    } ->
            rpc_action =
              Enum.find(rpc_actions, fn rpc_action ->
                if to_string(rpc_action.name) == rpc_spec["action"] do
                  rpc_action.action
                end
              end)

            if rpc_action do
              {resource, rpc_action}
            end
          end)

        if rpc_action == nil do
          raise "Unable to find rpc_action #{rpc_action["name"]}"
        end

        action = Ash.Resource.Info.action(resource, rpc_action.action)
        primary_key = Ash.Resource.Info.primary_key(resource)
        load = Helpers.parse_json_select_and_load(rpc_spec["load"] || [])
        select = Helpers.parse_json_select_and_load(rpc_spec["select"] || [])
        fields = (select ++ load) |> Enum.uniq()

        input_type_name = "#{snake_to_pascal(rpc_action.name)}Input"

        input_type =
          case action.type do
            :read ->
              if Enum.empty?(action.arguments) do
                ""
              else
                """
                export type #{input_type_name} = {
                #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
                }
                """
              end

            :update ->
              """
              export type #{input_type_name} = {
              #{Enum.map_join((primary_key ++ action.accept) |> Enum.uniq(), "\n", &get_action_accept_spec(&1, resource))}
              #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
              }
              """

            :action ->
              if Enum.empty?(action.arguments) do
                ""
              else
                """
                export type #{input_type_name} = {
                #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
                }
                """
              end

            _ ->
              """
              export type #{input_type_name} = {
              #{Enum.map_join(action.arguments, "\n", &get_action_argument_spec(&1))}
              #{Enum.map_join(action.accept, "\n", &get_action_accept_spec(&1, resource))}
              }
              """
          end

        return_type_name = "#{snake_to_pascal(rpc_action.name)}Return"

        return_type =
          if action.type == :action do
            build_generic_action_return_type(action, return_type_name, select, load, otp_app)
          else
            """
            export type #{return_type_name} = {
            #{Enum.map_join(fields,
            "\n",
            &get_field_spec(&1, resource))}
            }#{if action.type == :read and not action.get?, do: "[]", else: ""}
            """
          end

        validate_function =
          if action.type in [:read, :action] or not action_has_input?(action) do
            ""
          else
            build_validate_function(rpc_spec, endpoint_validate_arg)
          end

        Enum.join(
          [
            content,
            input_type,
            return_type,
            build_payload_function(rpc_spec, action),
            build_process_function(rpc_spec, action, endpoint_process_arg),
            validate_function
          ],
          "\n"
        )
      end)

    File.write!(output_file, types)
  end

  defp action_has_input?(action) do
    case action.type do
      :read -> not Enum.empty?(action.arguments)
      :action -> not Enum.empty?(action.arguments)
      _ -> not Enum.empty?(action.arguments) or not Enum.empty?(action.accept)
    end
  end

  defp build_rpc_action_input_type_name(rpc_action_name),
    do: "#{snake_to_pascal(rpc_action_name)}Input"

  defp build_rpc_action_return_type_name(rpc_action_name),
    do: "#{snake_to_pascal(rpc_action_name)}Return"

  defp build_payload(rpc_spec, action) do
    action_payload = "action: \"#{rpc_spec["action"]}\""

    input =
      if action_has_input?(action) do
        "input"
      else
        "input: {}"
      end

    select =
      if Map.get(rpc_spec, "select", []) |> Enum.empty?() do
        "select: []"
      else
        "select: #{Jason.encode!(rpc_spec["select"])}"
      end

    load =
      if Map.get(rpc_spec, "load", []) |> Enum.empty?() do
        "load: []"
      else
        "load: #{Jason.encode!(rpc_spec["load"])}"
      end

    Enum.join([action_payload, input, select, load], ", ")
  end

  defp build_payload_function(rpc_spec, action) do
    input_type = build_rpc_action_input_type_name(rpc_spec["action"])

    input_arg =
      if action_has_input?(action) do
        "input: #{input_type}"
      else
        ""
      end

    payload = build_payload(rpc_spec, action)

    return_type =
      if action_has_input?(action) do
        "{action: string, input: #{input_type}, select: string[], load: AshLoadList}"
      else
        "{action: string, input: {}, select: string[], load: AshLoadList}"
      end

    """
    export function build#{snake_to_pascal(rpc_spec["action"])}Payload(#{input_arg}): #{return_type} {
      return {#{payload}}
    }
    """
  end

  defp build_process_function(rpc_spec, action, endpoint_process_arg) do
    input_type = build_rpc_action_input_type_name(rpc_spec["action"])

    function_args =
      if action_has_input?(action) do
        "input: #{input_type}, #{endpoint_process_arg}"
      else
        endpoint_process_arg
      end

    payload = build_payload(rpc_spec, action)

    return_type = build_rpc_action_return_type_name(rpc_spec["action"])

    """
    export async function #{snake_to_camel(rpc_spec["action"])}(#{function_args}): Promise<{success: true, data: #{return_type}, error: null} | {success: false, data: null, error: Record<string, string>}> {
      const csrfToken = getCSRFToken();
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      };

      if (csrfToken) {
        headers['X-CSRF-Token'] = csrfToken;
      }

      return await fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({#{payload}})
      }).then(async (response) => {
        if (response.ok) {
          return response.json();
        } else {
          let errorMessage = `HTTP error ${response.status}`;
          try {
            const errorData = await response.json();
            errorMessage = errorData.message || JSON.stringify(errorData);
          } catch {
            // fallback if response is not JSON
            const text = await response.text();
            if (text) errorMessage = text;
          }
          throw new Error(errorMessage);
        }
      })
    }
    """
  end

  defp build_validate_function(rpc_spec, endpoint_validate_arg) do
    input_type = build_rpc_action_input_type_name(rpc_spec["action"])

    function_args = "input: #{input_type}, #{endpoint_validate_arg}"

    """
    export async function validate#{snake_to_pascal(rpc_spec["action"])}(#{function_args}): Promise<{success: true, errors: Record<string, string>}> {
      const csrfToken = getCSRFToken();
      const headers: Record<string, string> = {
        'Content-Type': 'application/json'
      };

      if (csrfToken) {
        headers['X-CSRF-Token'] = csrfToken;
      }

      return await fetch(endpoint, {
        method: 'POST',
        headers,
        body: JSON.stringify({action: "#{rpc_spec["action"]}", input})
      }).then(async (response) => {
        if (response.ok) {
          return response.json();
        } else {
          let errorMessage = `HTTP error ${response.status}`;
          try {
            const errorData = await response.json();
            errorMessage = errorData.message || JSON.stringify(errorData);
          } catch {
            // fallback if response is not JSON
            const text = await response.text();
            if (text) errorMessage = text;
          }
          throw new Error(errorMessage);
        }
      })
    }
    """
  end

  defp snake_to_pascal(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_pascal()
  end

  defp snake_to_pascal(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn {part, _} -> String.capitalize(part) end)
    |> Enum.join()
  end

  defp snake_to_camel(snake) when is_atom(snake) do
    snake
    |> Atom.to_string()
    |> snake_to_camel()
  end

  defp snake_to_camel(snake) when is_binary(snake) do
    snake
    |> String.split("_")
    |> Enum.with_index()
    |> Enum.map(fn
      {part, 0} -> String.downcase(part)
      {part, _} -> String.capitalize(part)
    end)
    |> Enum.join()
  end

  defp get_field_spec(field, resource) when is_atom(field) do
    attributes =
      if field == :id,
        do: [Ash.Resource.Info.attribute(resource, :id)],
        else: Ash.Resource.Info.public_attributes(resource)

    calculations = Ash.Resource.Info.public_calculations(resource)
    aggregates = Ash.Resource.Info.public_aggregates(resource)

    with nil <- Enum.find(attributes, &(&1.name == field)),
         nil <- Enum.find(calculations, &(&1.name == field)),
         nil <- Enum.find(aggregates, &(&1.name == field)) do
      throw("Field not found: #{resource}.#{field}" |> String.replace("Elixir.", ""))
    else
      %Ash.Resource.Attribute{} = attr ->
        if attr.allow_nil? do
          "  #{field}?: #{get_ts_type(attr)} | null;"
        else
          "  #{field}: #{get_ts_type(attr)};"
        end

      %Ash.Resource.Calculation{} = calc ->
        if calc.allow_nil? do
          "  #{field}?: #{get_ts_type(calc)} | null;"
        else
          "  #{field}: #{get_ts_type(calc)};"
        end

      %Ash.Resource.Aggregate{} = agg ->
        type =
          case agg.kind do
            :sum ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            :first ->
              resource
              |> lookup_aggregate_type(agg.relationship_path, agg.field)
              |> get_ts_type()

            _ ->
              get_ts_type(agg.kind)
          end

        if agg.include_nil? do
          "  #{field}?: #{type} | null;"
        else
          "  #{field}: #{type};"
        end

      field ->
        throw("Unknown field type: #{inspect(field)}")
    end
  end

  defp get_field_spec({field_name, fields}, resource) do
    relationships = Ash.Resource.Info.public_relationships(resource)

    case Enum.find(relationships, &(&1.name == field_name)) do
      nil ->
        throw("Relationship not found on #{resource}: #{field_name}")

      %Ash.Resource.Relationships.HasMany{} = rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_field_spec(&1, rel.destination))}\n}[];\n"

      rel ->
        id_fields = Ash.Resource.Info.primary_key(resource)
        fields = Enum.uniq(fields ++ id_fields)

        if rel.allow_nil? do
          "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_field_spec(&1, rel.destination))}} | null;"
        else
          "  #{field_name}: {#{Enum.map_join(fields, "\n", &get_field_spec(&1, rel.destination))}};\n"
        end
    end
  end

  defp get_action_accept_spec(attr, resource) do
    attribute = Ash.Resource.Info.attribute(resource, attr)

    if attribute.allow_nil? or attribute.default != nil do
      "  #{attr}?: #{get_ts_type(attribute)} | null;"
    else
      "  #{attr}: #{get_ts_type(attribute)};"
    end
  end

  defp get_action_argument_spec(argument) do
    if argument.allow_nil? or argument.default != nil do
      "  #{argument.name}?: #{get_ts_type(argument)} | null;"
    else
      "  #{argument.name}: #{get_ts_type(argument)};"
    end
  end

  defp lookup_aggregate_type(current_resource, [], field) do
    Ash.Resource.Info.attribute(current_resource, field)
  end

  defp lookup_aggregate_type(current_resource, relationship_path, field) do
    [next_resource | rest] = relationship_path

    relationship =
      Enum.find(Ash.Resource.Info.relationships(current_resource), &(&1.name == next_resource))

    lookup_aggregate_type(relationship.destination, rest, field)
  end

  defp build_generic_action_return_type(action, return_type_name, select, load, otp_app) do
    cond do
      action.returns in [Ash.Type.Struct, {:array, Ash.Type.Struct}] ->
        instance_of = action.constraints[:instance_of]

        is_array = is_tuple(action.returns)

        app_resources =
          otp_app
          |> Ash.Info.domains()
          |> Enum.flat_map(fn d -> Ash.Domain.Info.resources(d) end)

        resource = Enum.find(app_resources, &(&1 == instance_of))

        if resource do
          """
          export type #{return_type_name} = {
          #{Enum.map_join(select ++ load,
          "\n",
          &get_field_spec(&1, resource))}
          }#{if is_array, do: "[]", else: ""}
          """
        else
          if load != [] do
            raise "Cannot use load with generic action #{action.name}, since it does not return a resource."
          end

          """
          export type #{return_type_name} = {
          #{Enum.map_join(select,
          "\n",
          &"#{&1}?: any")}
          }#{if is_array, do: "[]", else: ""}
          """
        end

      action.returns in [:map, Ash.Type.Map, {:array, :map}, {:array, Ash.Type.Map}] ->
        if load != [] do
          raise "Cannot use load with generic action #{action.name}, since it does not return a resource."
        end

        is_array = is_tuple(action.returns)

        """
        export type #{return_type_name} = {
          #{Enum.map_join(select,
        "\n",
        &"#{&1}?: any")}
        }#{if is_array, do: "[]", else: ""}
        """

      true ->
        if load != [] do
          raise "Cannot use load with generic action #{action.name}, since it does not return a resource."
        end

        get_ts_type(%{type: action.returns, constraints: action.constraints})
    end
  end

  defp get_ts_type(%{type: nil}), do: "null"
  defp get_ts_type(%{type: :sum}), do: "number"
  defp get_ts_type(%{type: :count}), do: "number"
  defp get_ts_type(%{type: :map}), do: "Record<string, any>"
  defp get_ts_type(%{type: Ash.Type.Atom}), do: "string"
  defp get_ts_type(%{type: Ash.Type.UUID}), do: "string"
  defp get_ts_type(%{type: Ash.Type.String}), do: "string"
  defp get_ts_type(%{type: Ash.Type.UtcDatetime}), do: "string"
  defp get_ts_type(%{type: Ash.Type.UtcDatetimeUsec}), do: "string"
  defp get_ts_type(%{type: Ash.Type.Date}), do: "string"
  defp get_ts_type(%{type: Ash.Type.DateTime}), do: "string"
  defp get_ts_type(%{type: Ash.Type.Time}), do: "string"
  defp get_ts_type(%{type: Ash.Type.Map}), do: "Record<string, any>"
  defp get_ts_type(%{type: Ash.Type.CiString}), do: "string"
  defp get_ts_type(%{type: Ash.Type.Integer}), do: "number"
  defp get_ts_type(%{type: Ash.Type.Boolean}), do: "boolean"
  defp get_ts_type(%{type: Ash.Type.Float}), do: "number"
  defp get_ts_type(%{type: Ash.Type.Keyword}), do: "string"
  defp get_ts_type(%{type: AshDoubleEntry.ULID}), do: "string"
  defp get_ts_type(%{type: AshMoney.Types.Money}), do: "{currency: string, amount: string}"

  defp get_ts_type(%{type: type, constraints: constraints} = attr) do
    cond do
      Ash.Type.NewType.new_type?(type) ->
        sub_type_constraints = Ash.Type.NewType.constraints(type, constraints)
        subtype = Ash.Type.NewType.subtype_of(type)

        get_ts_type(%{attr | type: subtype, constraints: sub_type_constraints})

      Spark.implements_behaviour?(type, Ash.Type.Enum) ->
        type.values() |> Enum.map(&"\"#{to_string(&1)}\"") |> Enum.join(" | ")

      true ->
        raise "unsupported type #{inspect(type)}"
    end
  end
end
