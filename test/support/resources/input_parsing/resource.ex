# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.InputParsing.Resource do
  @moduledoc """
  Test resource specifically designed to stress test input parsing functionality.

  This resource covers all the edge cases from the input-parsing implementation plan:
  1. Standard snake_case Elixir fields with camelCase formatter
  2. Fields with DSL field_names mappings (problematic characters like ? and numeric suffixes)
  3. Arguments with DSL argument_names mappings
  4. Nested embedded resources with various field name formats
  5. Types with typescript_field_names/0 callback
  6. Union types with various member formats
  7. Tuple type with typescript_field_names callback
  8. Keyword type with typescript_field_names callback
  9. Deeply nested typed maps (outer → inner with field_names at each level)
  10. 3-level embedded resource nesting (Resource → NestedProfile → Profile)
  11. Union with :map_with_tag storage
  12. Array of unions with embedded resource members
  13. Generic action with embedded resource argument
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "InputParsingResource"

    # DSL field_names mappings - maps problematic Elixir names to exact TypeScript names
    # String values are used directly without additional formatting
    field_names(
      is_active?: "isActive",
      has_data?: "hasData",
      version_1: "version1"
    )

    # DSL argument_names mappings for actions
    # String values are used directly without additional formatting
    argument_names(
      search: [include_deleted?: "includeDeleted", filter_by_1?: "filterBy1"],
      create_with_args: [is_urgent?: "isUrgent", priority_1: "priority1"]
    )
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    # Standard snake_case fields - should work with default camelCase formatting
    # :user_name → "userName", :email_address → "emailAddress"
    attribute :user_name, :string do
      allow_nil? false
      public? true
    end

    attribute :email_address, :string do
      allow_nil? false
      public? true
    end

    # Additional standard snake_case field
    attribute :display_name, :string do
      allow_nil? true
      public? true
    end

    # Fields that need DSL mapping (problematic characters)
    # :is_active? → "isActive" (via field_names mapping)
    attribute :is_active?, :boolean do
      default true
      public? true
    end

    # :has_data? → "hasData" (via field_names mapping)
    attribute :has_data?, :boolean do
      default false
      public? true
    end

    # :version_1 → "version1" (via field_names mapping)
    attribute :version_1, :integer do
      default 1
      public? true
    end

    # Typed map with field constraints (standard snake_case)
    attribute :settings, :map do
      public? true

      constraints fields: [
                    notification_enabled: [type: :boolean, allow_nil?: false],
                    theme_name: [type: :string, allow_nil?: true],
                    retry_count: [type: :integer, allow_nil?: true]
                  ]
    end

    # Typed map using a NewType with typescript_field_names callback
    # Tests: total_count_1 → totalCount1, is_complete? → isComplete
    attribute :stats, AshTypescript.Test.InputParsing.Stats do
      public? true
    end

    # Embedded resource with its own field mappings
    # Tests: bio_text_1 → bioText1, is_public? → isPublic
    attribute :profile_data, AshTypescript.Test.InputParsing.Profile do
      public? true
    end

    # Array of embedded resources
    # Tests: change_count_1 → changeCount1, was_reverted? → wasReverted
    attribute :history, {:array, AshTypescript.Test.InputParsing.HistoryEntry} do
      default []
      public? true
    end

    # Union type with embedded resources and NewType map member
    attribute :content, :union do
      public? true

      constraints types: [
                    # Embedded resource member (has its own field_names)
                    text: [
                      type: AshTypescript.Test.InputParsing.TextContent,
                      tag: :content_type,
                      tag_value: "text"
                    ],
                    # NewType map member with typescript_field_names
                    data: [
                      type: AshTypescript.Test.InputParsing.DataContentMap,
                      tag: :content_type,
                      tag_value: "data"
                    ],
                    # Simple type member (no special handling needed)
                    simple_value: [type: :string]
                  ],
                  storage: :type_and_value
    end

    # =========================================================================
    # NEW: Additional attributes for exhaustive input parsing coverage
    # =========================================================================

    # Tuple type with typescript_field_names callback
    # Tests: lat_1 → lat1, lng_1 → lng1, is_verified? → isVerified
    attribute :location, AshTypescript.Test.InputParsing.LocationTuple do
      public? true
    end

    # Keyword type with typescript_field_names callback
    # Tests: theme_1 → theme1, is_dark_mode? → isDarkMode
    attribute :preferences, AshTypescript.Test.InputParsing.PreferencesKeyword do
      public? true
    end

    # Deeply nested typed maps with field_names at each level
    # Tests: outer (is_enabled_1? → isEnabled1) → inner (max_retries_1 → maxRetries1, is_cached? → isCached)
    attribute :deep_settings, AshTypescript.Test.InputParsing.DeepNestedSettings do
      public? true
    end

    # 3-level embedded resource nesting
    # Tests: Resource → NestedProfile (level_1?, has_details?) → Profile (bio_text_1, is_public?)
    attribute :nested_profile, AshTypescript.Test.InputParsing.NestedProfile do
      public? true
    end

    # Union with :map_with_tag storage (different from :type_and_value)
    # Tests input parsing for map_with_tag storage mode
    # Note: map_with_tag requires ALL members to have tags
    attribute :tagged_status, :union do
      public? true

      constraints types: [
                    active: [
                      type: AshTypescript.Test.InputParsing.TaggedStatus,
                      tag: :status_type,
                      tag_value: "active"
                    ],
                    inactive: [
                      type: AshTypescript.Test.InputParsing.TaggedStatus,
                      tag: :status_type,
                      tag_value: "inactive"
                    ]
                  ],
                  storage: :map_with_tag
    end

    # Array of unions with embedded resource members having field_names
    # Tests array union input with field mappings
    attribute :attachments, {:array, :union} do
      public? true
      default []

      constraints items: [
                    types: [
                      file: [
                        type: AshTypescript.Test.InputParsing.AttachmentFile,
                        tag: :attachment_type,
                        tag_value: "file"
                      ],
                      link: [
                        type: AshTypescript.Test.InputParsing.AttachmentLink,
                        tag: :attachment_type,
                        tag_value: "link"
                      ],
                      # Simple string member for comparison
                      note: [type: :string]
                    ]
                  ]
    end

    create_timestamp :created_at do
      public? true
    end

    update_timestamp :updated_at
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
    end

    read :get_by_id do
      get_by :id
    end

    # Search action with mapped argument names
    # Tests: include_deleted? → includeDeleted, filter_by_1? → filterBy1
    read :search do
      argument :query, :string, allow_nil?: false

      argument :include_deleted?, :boolean do
        default false
      end

      argument :filter_by_1?, :boolean do
        default false
      end

      filter expr(contains(user_name, ^arg(:query)) or contains(email_address, ^arg(:query)))
    end

    create :create do
      primary? true

      accept [
        :user_name,
        :email_address,
        :display_name,
        :is_active?,
        :has_data?,
        :version_1,
        :settings,
        :stats,
        :profile_data,
        :history,
        :content,
        # New attributes for exhaustive coverage
        :location,
        :preferences,
        :deep_settings,
        :nested_profile,
        :tagged_status,
        :attachments
      ]
    end

    # Create action with mapped argument names
    # Tests: is_urgent? → isUrgent, priority_1 → priority1
    create :create_with_args do
      accept [
        :user_name,
        :email_address,
        :is_active?,
        :has_data?,
        :settings
      ]

      argument :is_urgent?, :boolean do
        default false
      end

      argument :priority_1, :integer do
        default 1
      end

      argument :extra_data, :map do
        allow_nil? true
      end
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :user_name,
        :email_address,
        :display_name,
        :is_active?,
        :has_data?,
        :version_1,
        :settings,
        :stats,
        :profile_data,
        :history,
        :content,
        # New attributes for exhaustive coverage
        :location,
        :preferences,
        :deep_settings,
        :nested_profile,
        :tagged_status,
        :attachments
      ]
    end

    # Generic action to test input/output with NewType argument
    # Tests: is_valid? → isValid (via InputDataMap's typescript_field_names)
    action :process_data, :map do
      constraints fields: [
                    processed: [type: :boolean, allow_nil?: false],
                    result_count: [type: :integer, allow_nil?: false]
                  ]

      # Uses NewType with typescript_field_names for field mapping
      argument :input_data, AshTypescript.Test.InputParsing.InputDataMap do
        allow_nil? false
      end

      # Uses NewType with typescript_field_names
      # Tests: cache_enabled_1? → cacheEnabled1
      argument :options, AshTypescript.Test.InputParsing.Options do
        allow_nil? true
      end

      run fn input, _context ->
        {:ok,
         %{
           processed: true,
           result_count: 1
         }}
      end
    end

    # Generic action with embedded resource argument
    # Tests input formatting when argument is a full embedded resource
    action :process_profile, AshTypescript.Test.InputParsing.ProcessProfileResult do
      # Embedded resource as action argument
      argument :profile, AshTypescript.Test.InputParsing.Profile do
        allow_nil? false
      end

      # Optional nested profile for deeper nesting test
      argument :nested, AshTypescript.Test.InputParsing.NestedProfile do
        allow_nil? true
      end

      run fn input, _context ->
        profile = input.arguments.profile

        {:ok,
         %{
           profile_name: profile.display_name,
           is_processed?: true
         }}
      end
    end
  end
end
