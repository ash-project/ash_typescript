# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TypedChannel.UnlistedStep do
  @moduledoc """
  Embedded resource that no RPC resource references, so it is absent from the
  manifest. Has a private attribute that must never reach the wire.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil

  attributes do
    attribute :tool_name, :string, public?: true
    attribute :duration_ms, :integer, public?: true
    attribute :secret_token, :string, public?: false
  end
end

defmodule AshTypescript.Test.TypedChannel.UnlistedDetail do
  @moduledoc """
  Embedded resource absent from the manifest, nested inside another one.
  Derives `Jason.Encoder` for every field, so only the formatter keeps its
  private attribute off the wire.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil

  @derive {Jason.Encoder, except: [:__meta__]}

  attributes do
    attribute :label, :string, public?: true
    attribute :secret_note, :string, public?: false
  end
end

defmodule AshTypescript.Test.TypedChannel.UnlistedRichStep do
  @moduledoc """
  Embedded resource absent from the manifest whose fields need type-aware
  formatting: a scalar struct, nested embedded resources and a union.
  """
  use Ash.Resource, data_layer: :embedded, domain: nil

  attributes do
    attribute :elapsed, :duration, public?: true
    attribute :detail, AshTypescript.Test.TypedChannel.UnlistedDetail, public?: true
    attribute :details, {:array, AshTypescript.Test.TypedChannel.UnlistedDetail}, public?: true

    attribute :outcome, :union,
      public?: true,
      constraints: [types: [note: [type: :string], finished_at: [type: :date]]]
  end
end

defmodule AshTypescript.Test.TypedChannel.UnlistedOwner do
  @moduledoc "Resource absent from the manifest, related from `UnlistedTask`."
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key :id, public?: true
    attribute :name, :string, public?: true
    attribute :password_hash, :string, public?: false
  end
end

defmodule AshTypescript.Test.TypedChannel.UnlistedTask do
  @moduledoc "Resource absent from the manifest, with to-one and to-many relationships."
  use Ash.Resource, domain: nil

  attributes do
    uuid_primary_key :id, public?: true
    attribute :title, :string, public?: true
    attribute :took, :duration, public?: true
  end

  relationships do
    belongs_to :owner, AshTypescript.Test.TypedChannel.UnlistedOwner,
      public?: true,
      attribute_public?: false

    has_many :watchers, AshTypescript.Test.TypedChannel.UnlistedOwner,
      public?: true,
      destination_attribute: :id
  end
end

defmodule AshTypescript.Test.TypedChannel.EncoderHiddenCredentials do
  @moduledoc """
  A non-scalar struct whose `Jason.Encoder` hides a field. Under a `:term`
  position the formatter must leave it to its encoder.
  """
  @derive {Jason.Encoder, only: [:public_part]}
  defstruct [:public_part, :password]
end

defmodule AshTypescript.Test.TypedChannel.EmbeddedPayloadItem do
  @moduledoc """
  Publications whose payloads carry embedded resource structs (issue #105).
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  @checklist_union [
    type: :union,
    constraints: [
      types: [
        checklist: [
          type: AshTypescript.Test.TodoContent.ChecklistContent,
          tag: :content_type,
          tag_value: "checklist"
        ],
        note: [type: :string]
      ],
      storage: :type_and_value
    ]
  ]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "embedded_payload"

    publish :create, [:id],
      event: "metadata_direct",
      public?: true,
      returns: AshTypescript.Test.TodoMetadata,
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "metadata_in_map",
      public?: true,
      returns: :map,
      constraints: [
        fields: [
          input_tokens: [type: :integer],
          primary_metadata: [type: AshTypescript.Test.TodoMetadata],
          metadata_steps: [type: {:array, AshTypescript.Test.TodoMetadata}],
          content_value: @checklist_union
        ]
      ],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "nested_profile",
      public?: true,
      returns: AshTypescript.Test.InputParsing.NestedProfile,
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "todo_record",
      public?: true,
      returns: :struct,
      constraints: [instance_of: AshTypescript.Test.Todo],
      transform: fn notification -> notification.data end

    publish :create, [:id],
      event: "term_values",
      public?: true,
      returns: :map,
      constraints: [fields: [credentials: [type: :term], took: [type: :term]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "unlisted_rich_step",
      public?: true,
      returns: :map,
      constraints: [fields: [step: [type: AshTypescript.Test.TypedChannel.UnlistedRichStep]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "unlisted_task",
      public?: true,
      returns: :struct,
      constraints: [instance_of: AshTypescript.Test.TypedChannel.UnlistedTask],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "unlisted_steps",
      public?: true,
      returns: :map,
      constraints: [
        fields: [steps: [type: {:array, AshTypescript.Test.TypedChannel.UnlistedStep}]]
      ],
      transform: fn _notification -> nil end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :create]
  end
end

defmodule AshTypescript.Test.TypedChannel.ObjectKindsItem do
  @moduledoc """
  Publications for every map-like payload kind the typed channel verifier
  accepts (issue #104), pushed through Phoenix's JSON serializer below.
  """
  use Ash.Resource,
    domain: nil,
    notifiers: [Ash.Notifier.PubSub]

  pub_sub do
    module AshTypescript.Test.TestEndpoint
    prefix "object_kinds"

    publish :create, [:id],
      event: "as_union",
      public?: true,
      returns: :union,
      constraints: [types: [note: [type: :string], count: [type: :integer]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_keyword",
      public?: true,
      returns: :keyword,
      constraints: [fields: [item_count: [type: :integer]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_tuple",
      public?: true,
      returns: :tuple,
      constraints: [fields: [item_count: [type: :integer], label: [type: :string]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_typed_struct",
      public?: true,
      returns: :struct,
      constraints: [fields: [item_count: [type: :integer]]],
      transform: fn _notification -> nil end

    publish :create, [:id],
      event: "as_map_new_type",
      public?: true,
      returns: AshTypescript.Test.CustomMetadata,
      transform: fn _notification -> nil end

    # Refused by the verifier when declared in a typed channel; kept here to
    # show what Phoenix does with it.
    publish :create, [:id],
      event: "as_string",
      public?: true,
      returns: :string,
      transform: fn _notification -> nil end
  end

  attributes do
    uuid_primary_key :id
  end

  actions do
    defaults [:read, :create]
  end
end

defmodule AshTypescript.TypedChannel.PayloadFormatterTest do
  use ExUnit.Case, async: true

  @moduletag :ash_typescript

  alias AshTypescript.Test.InputParsing.NestedProfile
  alias AshTypescript.Test.InputParsing.Profile
  alias AshTypescript.Test.TodoContent.ChecklistContent
  alias AshTypescript.Test.TodoMetadata
  alias AshTypescript.Test.TypedChannel.EmbeddedPayloadItem
  alias AshTypescript.Test.TypedChannel.EncoderHiddenCredentials
  alias AshTypescript.Test.TypedChannel.ObjectKindsItem
  alias AshTypescript.Test.TypedChannel.UnlistedDetail
  alias AshTypescript.Test.TypedChannel.UnlistedOwner
  alias AshTypescript.Test.TypedChannel.UnlistedRichStep
  alias AshTypescript.Test.TypedChannel.UnlistedStep
  alias AshTypescript.Test.TypedChannel.UnlistedTask
  alias AshTypescript.TypedChannel.PayloadFormatter

  defp metadata(attrs \\ %{}) do
    struct!(
      TodoMetadata,
      Map.merge(
        %{
          category: "work",
          priority_score: 5,
          external_reference: "EXT-1",
          is_urgent: true,
          deadline: ~D[2026-01-15],
          estimated_duration: Duration.new!(hour: 1),
          internal_notes: "do not leak"
        },
        attrs
      )
    )
  end

  defp format(event, payload),
    do: PayloadFormatter.format_payload(EmbeddedPayloadItem, event, payload)

  describe "embedded resource as the publication returns type" do
    test "formats public fields with client names and drops private ones" do
      formatted = format("metadata_direct", metadata())

      assert formatted["category"] == "work"
      assert formatted["priorityScore"] == 5
      assert formatted["externalReference"] == "EXT-1"
      assert formatted["isUrgent"] == true
      assert formatted["deadline"] == "2026-01-15"
      assert formatted["estimatedDuration"] == "PT1H"

      refute Map.has_key?(formatted, "internalNotes")
      refute Map.has_key?(formatted, :internal_notes)
      refute Enum.any?(Map.keys(formatted), &is_atom/1)
    end

    test "unloaded calculations become nil instead of leaking Ash.NotLoaded" do
      formatted = format("metadata_direct", metadata())

      assert Map.has_key?(formatted, "displayCategory")
      assert formatted["displayCategory"] == nil
    end

    test "forbidden fields become nil and never expose the original value" do
      forbidden = %Ash.ForbiddenField{field: :category, type: :attribute}

      formatted =
        format("metadata_direct", metadata(%{category: forbidden, priority_info: forbidden}))

      assert formatted["category"] == nil
      assert formatted["priorityInfo"] == nil
    end

    test "nested embedded resources and field_names mappings are formatted" do
      payload =
        struct!(NestedProfile,
          section_name: "About",
          level_1?: true,
          has_details?: false,
          detail_profile:
            struct!(Profile,
              display_name: "Ada",
              bio_text_1: "Hello",
              is_public?: true,
              follower_count: 3
            )
        )

      assert format("nested_profile", payload) == %{
               "sectionName" => "About",
               "level1" => true,
               "hasDetails" => false,
               "detailStats" => nil,
               "detailProfile" => %{
                 "displayName" => "Ada",
                 "bioText1" => "Hello",
                 "isPublic" => true,
                 "followerCount" => 3
               }
             }
    end
  end

  describe "embedded resources inside a typed map payload" do
    test "single and array embedded fields are formatted" do
      formatted =
        format("metadata_in_map", %{
          input_tokens: 10,
          primary_metadata: metadata(),
          metadata_steps: [metadata(%{priority_score: 1}), metadata(%{priority_score: 2})]
        })

      assert formatted["inputTokens"] == 10
      assert formatted["primaryMetadata"]["priorityScore"] == 5
      refute Map.has_key?(formatted["primaryMetadata"], "internalNotes")

      assert Enum.map(formatted["metadataSteps"], & &1["priorityScore"]) == [1, 2]
      assert Enum.all?(formatted["metadataSteps"], &(not Map.has_key?(&1, "internalNotes")))
    end

    test "union values holding embedded resources are formatted per member" do
      checklist =
        struct!(ChecklistContent,
          title: "Groceries",
          is_active?: false,
          allow_reordering: true,
          content_type: "checklist",
          items: []
        )

      formatted =
        format("metadata_in_map", %{
          content_value: %Ash.Union{type: :checklist, value: checklist}
        })

      assert %{"contentValue" => %{"checklist" => member}} = formatted
      assert member["title"] == "Groceries"
      assert member["isActive"] == false
      assert member["allowReordering"] == true
      assert member["contentType"] == "checklist"
      assert member["totalItems"] == nil
    end

    test "union values holding a primitive member are formatted" do
      assert format("metadata_in_map", %{content_value: %Ash.Union{type: :note, value: "hi"}}) ==
               %{"contentValue" => %{"note" => "hi"}}
    end

    test "embedded resources missing from the manifest expose public fields only" do
      step = struct!(UnlistedStep, tool_name: "search", duration_ms: 1234, secret_token: "s3")

      assert format("unlisted_steps", %{steps: [step]}) == %{
               "steps" => [%{"toolName" => "search", "durationMs" => 1234}]
             }
    end
  end

  describe ":term values" do
    test "non-scalar structs are left untouched and scalar structs are normalized" do
      credentials = %EncoderHiddenCredentials{public_part: "visible", password: "hunter2"}

      assert format("term_values", %{credentials: credentials, took: Duration.new!(hour: 1)}) ==
               %{"credentials" => credentials, "took" => "PT1H"}
    end
  end

  describe "embedded resources missing from the manifest" do
    defp rich_step do
      struct!(UnlistedRichStep,
        elapsed: Duration.new!(minute: 5),
        detail: struct!(UnlistedDetail, label: "one", secret_note: "s1"),
        details: [struct!(UnlistedDetail, label: "two", secret_note: "s2")],
        outcome: %Ash.Union{type: :finished_at, value: ~D[2026-03-01]}
      )
    end

    test "fields are formatted by their Ash type" do
      refute Map.has_key?(AshTypescript.resource_lookup(), UnlistedRichStep)
      refute Map.has_key?(AshTypescript.resource_lookup(), UnlistedDetail)

      assert format("unlisted_rich_step", %{step: rich_step()}) == %{
               "step" => %{
                 "elapsed" => "PT5M",
                 "detail" => %{"label" => "one"},
                 "details" => [%{"label" => "two"}],
                 "outcome" => %{"finishedAt" => "2026-03-01"}
               }
             }
    end

    test "loaded relationships of an unlisted resource are reduced to public fields" do
      owner = fn name -> struct!(UnlistedOwner, id: name, name: name, password_hash: "x") end

      task =
        struct!(UnlistedTask,
          id: "t1",
          title: "Ship",
          took: Duration.new!(second: 30),
          owner: owner.("ada"),
          watchers: [owner.("bob")]
        )

      assert format("unlisted_task", task) == %{
               "id" => "t1",
               "title" => "Ship",
               "took" => "PT30S",
               "owner" => %{"id" => "ada", "name" => "ada"},
               "watchers" => [%{"id" => "bob", "name" => "bob"}]
             }
    end

    test "encode through Phoenix's JSON serializer without private nested fields" do
      :ok =
        PayloadFormatter.push_formatted(
          json_socket(),
          EmbeddedPayloadItem,
          "unlisted_rich_step",
          %{step: rich_step()}
        )

      assert pushed_payload() == %{
               "step" => %{
                 "elapsed" => "PT5M",
                 "detail" => %{"label" => "one"},
                 "details" => [%{"label" => "two"}],
                 "outcome" => %{"finishedAt" => "2026-03-01"}
               }
             }
    end
  end

  describe "non-embedded resource struct as the returns type" do
    test "formats public attributes and drops private ones and Ecto metadata" do
      todo =
        struct!(AshTypescript.Test.Todo,
          id: "8b2c6f8e-2a4c-4c39-9d1f-1d0a8f3f2b11",
          title: "Write tests",
          due_date: ~D[2026-02-01],
          metadata: metadata(),
          updated_at: ~U[2026-01-01 00:00:00Z]
        )

      formatted = format("todo_record", todo)

      assert formatted["title"] == "Write tests"
      assert formatted["dueDate"] == "2026-02-01"
      assert formatted["metadata"]["priorityScore"] == 5
      assert formatted["user"] == nil

      refute Map.has_key?(formatted, "updatedAt")
      refute Enum.any?(Map.keys(formatted), &is_atom/1)
      refute Enum.any?(Map.keys(formatted), &String.starts_with?(&1, "_"))
    end
  end

  describe "push_formatted/4 through Phoenix's JSON serializer" do
    defp json_socket do
      %Phoenix.Socket{
        joined: true,
        transport_pid: self(),
        topic: "embedded_payload:1",
        join_ref: "1",
        serializer: Phoenix.Socket.V2.JSONSerializer
      }
    end

    defp pushed_payload do
      assert_receive {:socket_push, :text, json}
      json |> IO.iodata_to_binary() |> Jason.decode!() |> List.last()
    end

    test "embedded resources without a Jason.Encoder encode with client field names" do
      :ok =
        PayloadFormatter.push_formatted(json_socket(), EmbeddedPayloadItem, "metadata_in_map", %{
          input_tokens: 10,
          metadata_steps: [metadata()]
        })

      assert %{"inputTokens" => 10, "metadataSteps" => [step]} = pushed_payload()
      assert step["priorityScore"] == 5
      assert step["externalReference"] == "EXT-1"
      assert step["deadline"] == "2026-01-15"
      assert step["estimatedDuration"] == "PT1H"
      refute Map.has_key?(step, "internalNotes")
      refute Map.has_key?(step, "internal_notes")
    end

    test "embedded and resource struct payloads encode as JSON objects" do
      :ok =
        PayloadFormatter.push_formatted(
          json_socket(),
          EmbeddedPayloadItem,
          "metadata_direct",
          metadata()
        )

      assert %{"priorityScore" => 5} = pushed_payload()

      todo = struct!(AshTypescript.Test.Todo, title: "Write tests")

      :ok =
        PayloadFormatter.push_formatted(json_socket(), EmbeddedPayloadItem, "todo_record", todo)

      assert %{"title" => "Write tests"} = pushed_payload()
    end

    test "union, keyword, tuple, struct and map NewType payloads encode as JSON objects" do
      push = &PayloadFormatter.push_formatted(json_socket(), ObjectKindsItem, &1, &2)

      :ok = push.("as_union", %Ash.Union{type: :note, value: "hi"})
      assert pushed_payload() == %{"note" => "hi"}

      :ok = push.("as_keyword", item_count: 2)
      assert pushed_payload() == %{"itemCount" => 2}

      :ok = push.("as_tuple", {2, "two"})
      assert pushed_payload() == %{"itemCount" => 2, "label" => "two"}

      :ok = push.("as_typed_struct", %{item_count: 4})
      assert pushed_payload() == %{"itemCount" => 4}

      :ok = push.("as_map_new_type", %{field_1: "a", is_active?: true, line_2: nil})
      assert pushed_payload() == %{"field1" => "a", "isActive" => true, "line2" => nil}
    end

    test "a scalar payload is refused by Phoenix's JSON serializer" do
      assert_raise ArgumentError, ~s(expected payload to be a map, got: "hi"), fn ->
        PayloadFormatter.push_formatted(json_socket(), ObjectKindsItem, "as_string", "hi")
      end
    end

    test "a struct under :term encodes through its own Jason.Encoder" do
      :ok =
        PayloadFormatter.push_formatted(json_socket(), EmbeddedPayloadItem, "term_values", %{
          credentials: %EncoderHiddenCredentials{public_part: "visible", password: "hunter2"}
        })

      assert pushed_payload() == %{"credentials" => %{"public_part" => "visible"}}
    end

    test "unlisted embedded resources encode without leaking private fields" do
      step = struct!(UnlistedStep, tool_name: "search", duration_ms: 1234, secret_token: "s3")

      :ok =
        PayloadFormatter.push_formatted(json_socket(), EmbeddedPayloadItem, "unlisted_steps", %{
          steps: [step]
        })

      assert pushed_payload() == %{"steps" => [%{"toolName" => "search", "durationMs" => 1234}]}
    end
  end
end
