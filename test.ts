export type TestPostFilterInput = {
  and?: Array<TestPostFilterInput>;
  or?: Array<TestPostFilterInput>;
  not?: Array<TestPostFilterInput>;

  id?: {
eq?: string;
notEq?: string;
in?: Array<string>;
notIn?: Array<string>;

  };

  title?: {
eq?: string;
notEq?: string;
in?: Array<string>;
notIn?: Array<string>;

  };

  content?: {
eq?: string;
notEq?: string;
in?: Array<string>;
notIn?: Array<string>;

  };

  published?: {
eq?: boolean;
notEq?: boolean;

  };

  view_count?: {
eq?: number;
notEq?: number;
greaterThan?: number;
greaterThanOrEqual?: number;
lessThan?: number;
lessThanOrEqual?: number;
in?: Array<number>;
notIn?: Array<number>;

  };

  rating?: {
eq?: string;
notEq?: string;
greaterThan?: string;
greaterThanOrEqual?: string;
lessThan?: string;
lessThanOrEqual?: string;
in?: Array<string>;
notIn?: Array<string>;

  };

  published_at?: {
eq?: string;
notEq?: string;
greaterThan?: string;
greaterThanOrEqual?: string;
lessThan?: string;
lessThanOrEqual?: string;
in?: Array<string>;
notIn?: Array<string>;

  };

  tags?: {
eq?: Array<string>;
notEq?: Array<string>;
in?: Array<Array<string>>;
notIn?: Array<Array<string>>;

  };

  status?: {
eq?: "draft" | "published" | "archived";
notEq?: "draft" | "published" | "archived";
in?: Array<"draft" | "published" | "archived">;
notIn?: Array<"draft" | "published" | "archived">;

  };

  metadata?: {
eq?: Record<string, any>;
notEq?: Record<string, any>;
in?: Array<Record<string, any>>;
notIn?: Array<Record<string, any>>;

  };

  author_id?: {
eq?: string;
notEq?: string;
in?: Array<string>;
notIn?: Array<string>;

  };

  author?: TestUserFilterInput;

  comments?: TestCommentFilterInput;

};
