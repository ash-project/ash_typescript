defmodule AshTypescript.Test.Todo do
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    primary_read_warning?: false,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "Todo"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
    end

    attribute :description, :string do
      public? true
    end

    attribute :completed, :boolean do
      default false
      public? true
    end

    attribute :status, AshTypescript.Test.Todo.Status do
      default :pending
      public? true
    end

    attribute :priority, :atom do
      constraints one_of: [:low, :medium, :high, :urgent]
      default :medium
      public? true
    end

    attribute :due_date, :date do
      public? true
    end

    attribute :priority_score, AshTypescript.Test.Todo.PriorityScore do
      public? true
    end

    attribute :color_palette, AshTypescript.Test.Todo.ColorPalette do
      public? true
    end

    attribute :tags, {:array, :string} do
      default []
      public? true
    end

    attribute :metadata, AshTypescript.Test.TodoMetadata do
      public? true
    end

    attribute :metadata_history, {:array, AshTypescript.Test.TodoMetadata} do
      default []
      public? true
    end

    # Union type attribute demonstrating tagged union with embedded resources
    attribute :content, :union do
      public? true

      constraints types: [
                    text: [
                      type: AshTypescript.Test.TodoContent.TextContent,
                      tag: :content_type,
                      tag_value: "text"
                    ],
                    checklist: [
                      type: AshTypescript.Test.TodoContent.ChecklistContent,
                      tag: :content_type,
                      tag_value: "checklist"
                    ],
                    link: [
                      type: AshTypescript.Test.TodoContent.LinkContent,
                      tag: :content_type,
                      tag_value: "link"
                    ],
                    # Simple types for testing untagged unions
                    note: [
                      type: :string
                    ],
                    priority_value: [
                      type: :integer,
                      constraints: [min: 1, max: 10]
                    ]
                  ],
                  storage: :type_and_value
    end

    # Union type array for testing array union support
    attribute :attachments, {:array, :union} do
      public? true
      default []

      constraints items: [
                    types: [
                      file: [
                        type: :map,
                        tag: :attachment_type,
                        tag_value: "file",
                        constraints: [
                          fields: [
                            filename: [type: :string, allow_nil?: false],
                            size: [type: :integer],
                            mime_type: [type: :string]
                          ]
                        ]
                      ],
                      image: [
                        type: :map,
                        tag: :attachment_type,
                        tag_value: "image",
                        constraints: [
                          fields: [
                            filename: [type: :string, allow_nil?: false],
                            width: [type: :integer],
                            height: [type: :integer],
                            alt_text: [type: :string]
                          ]
                        ]
                      ],
                      # Simple untagged union member
                      url: [
                        type: :string,
                        constraints: [match: ~r/^https?:\/\//]
                      ]
                    ]
                  ]
    end

    # Union type with :map_with_tag storage for testing alternative storage mode
    attribute :status_info, :union do
      public? true

      constraints types: [
                    simple: [
                      type: :map,
                      tag: :status_type,
                      tag_value: "simple"
                    ],
                    detailed: [
                      type: :map,
                      tag: :status_type,
                      tag_value: "detailed"
                    ],
                    automated: [
                      type: :map,
                      tag: :status_type,
                      tag_value: "automated"
                    ]
                  ],
                  storage: :map_with_tag
    end

    attribute :timestamp_info, AshTypescript.Test.TodoTimestamp do
      public? true
    end

    attribute :statistics, AshTypescript.Test.TodoStatistics do
      public? true
    end

    attribute :options, :keyword do
      public? true
      allow_nil? true

      constraints fields: [
                    priority: [
                      type: :integer,
                      allow_nil?: false,
                      description: "Priority level (1-10)",
                      constraints: [min: 1, max: 10]
                    ],
                    category: [
                      type: :string,
                      allow_nil?: true,
                      description: "Todo category",
                      constraints: [max_length: 50]
                    ],
                    notify: [
                      type: :boolean,
                      allow_nil?: true,
                      description: "Whether to send notifications"
                    ]
                  ]
    end

    attribute :coordinates, :tuple do
      public? true

      constraints fields: [
                    latitude: [
                      type: :float,
                      allow_nil?: false,
                      description: "Latitude coordinate",
                      constraints: [min: -90.0, max: 90.0]
                    ],
                    longitude: [
                      type: :float,
                      allow_nil?: false,
                      description: "Longitude coordinate",
                      constraints: [min: -180.0, max: 180.0]
                    ]
                  ]
    end

    create_timestamp :created_at do
      public? true
    end

    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, AshTypescript.Test.User do
      allow_nil? false
      public? true
    end

    has_many :comments, AshTypescript.Test.TodoComment do
      public? true
    end

    has_many :not_exposed_items, AshTypescript.Test.NotExposed do
      public? true
    end
  end

  aggregates do
    count :comment_count, :comments do
      public? true
    end

    count :helpful_comment_count, :comments do
      public? true
      filter expr(is_helpful == true)
    end

    exists :has_comments, :comments do
      public? true
    end

    avg :average_rating, :comments, :rating do
      public? true
    end

    max :highest_rating, :comments, :rating do
      public? true
    end

    first :latest_comment_content, :comments, :content do
      public? true
      sort created_at: :desc
    end

    list :comment_authors, :comments, :author_name do
      public? true
    end

    # Additional field-based aggregates
    first :latest_comment_id, :comments, :id do
      public? true
      sort created_at: :desc
    end

    list :recent_comment_ids, :comments, :id do
      public? true
      sort created_at: :desc
    end
  end

  calculations do
    calculate :is_overdue, :boolean, AshTypescript.Test.IsOverdueCalculation do
      public? true
    end

    calculate :days_until_due, :integer, AshTypescript.Test.Todo.SimpleDateCalculation do
      public? true
    end

    calculate :self, :struct, AshTypescript.Test.SelfCalculation do
      constraints instance_of: __MODULE__
      public? true

      argument :prefix, :string do
        allow_nil? true
        default nil
      end

      argument :count, :integer do
        allow_nil? true
        default nil
      end

      argument :enabled, :boolean do
        allow_nil? true
        default nil
      end

      argument :data, :map do
        allow_nil? true
        default nil
      end
    end

    calculate :summary,
              AshTypescript.Test.TodoStatistics,
              AshTypescript.Test.SummaryCalculation do
      public? true
    end
  end

  actions do
    defaults [:destroy]

    read :read do
      primary? true
      argument :filter_completed, :boolean

      argument :priority_filter, :atom do
        constraints one_of: [:low, :medium, :high, :urgent]
      end

      filter expr(
               if not is_nil(^arg(:filter_completed)) do
                 completed == ^arg(:filter_completed)
               else
                 true
               end and
                 if not is_nil(^arg(:priority_filter)) do
                   priority == ^arg(:priority_filter)
                 else
                   true
                 end
             )

      pagination offset?: true,
                 keyset?: true,
                 countable: true,
                 required?: false,
                 default_limit: 20,
                 max_page_size: 100
    end

    read :get_by_id do
      get_by [:id]
    end

    create :create do
      primary? true

      accept [
        :title,
        :description,
        :status,
        :priority,
        :due_date,
        :tags,
        :metadata,
        :metadata_history,
        :content,
        :attachments,
        :status_info,
        :priority_score,
        :color_palette,
        :timestamp_info,
        :statistics,
        :options,
        :coordinates
      ]

      argument :auto_complete, :boolean do
        default false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:completed, arg(:auto_complete))
      change manage_relationship(:user_id, :user, type: :append)
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :title,
        :description,
        :completed,
        :status,
        :priority,
        :due_date,
        :tags,
        :metadata,
        :content,
        :attachments,
        :status_info,
        :priority_score,
        :color_palette,
        :timestamp_info,
        :statistics,
        :options,
        :coordinates
      ]
    end

    update :complete do
      accept []
      change set_attribute(:completed, true)
    end

    update :set_priority do
      argument :priority, :atom do
        allow_nil? false
        constraints one_of: [:low, :medium, :high, :urgent]
      end

      change set_attribute(:priority, arg(:priority))
    end

    action :bulk_complete, {:array, :uuid} do
      argument :todo_ids, {:array, :uuid}, allow_nil?: false

      run fn input, _context ->
        # This would normally update multiple todos, but for testing we'll just return the IDs
        {:ok, input.arguments.todo_ids}
      end
    end

    action :get_statistics, :map do
      constraints fields: [
                    total: [type: :integer, allow_nil?: false],
                    completed: [type: :integer, allow_nil?: false],
                    pending: [type: :integer, allow_nil?: false],
                    overdue: [type: :integer, allow_nil?: false]
                  ]

      run fn _input, _context ->
        {:ok,
         %{
           total: 10,
           completed: 6,
           pending: 4,
           overdue: 2
         }}
      end
    end

    action :search, {:array, Ash.Type.Struct} do
      constraints items: [instance_of: __MODULE__]

      argument :query, :string, allow_nil?: false
      argument :include_completed, :boolean, default: true

      run fn _input, _context ->
        # This would normally search todos, but for testing we'll return empty
        {:ok, []}
      end
    end

    # Additional read action with different pagination configuration for testing
    read :search_paginated do
      argument :query, :string, allow_nil?: false
      argument :include_completed, :boolean, default: true

      filter expr(
               if not is_nil(^arg(:query)) do
                 contains(title, ^arg(:query)) or contains(description, ^arg(:query))
               else
                 true
               end and
                 if ^arg(:include_completed) do
                   true
                 else
                   completed != true
                 end
             )

      pagination offset?: true,
                 keyset?: false,
                 countable: true,
                 required?: true,
                 default_limit: 10,
                 max_page_size: 50
    end

    # Read action with keyset-only pagination
    read :list_recent do
      filter expr(created_at >= ago(7, :day))

      pagination required?: false,
                 offset?: false,
                 keyset?: true,
                 countable: false,
                 default_limit: 25,
                 max_page_size: 100
    end

    # Read action with no pagination (should not have page field)
    read :list_high_priority do
      filter expr(priority in [:high, :urgent])
    end
  end
end
