alter table "public"."bank_questions" add column "is_from_exercise" boolean not null default false;

alter table "public"."bank_questions" add column "is_image_needed" boolean not null default false;

alter table "public"."bank_questions" add column "is_incomplete" boolean not null default false;

alter table "public"."bank_questions" add column "is_solved_example" boolean not null default false;

alter table "public"."bank_questions" add column "is_true" boolean;

alter table "public"."bank_questions" add column "match_columns" text;

alter table "public"."bank_questions" add column "svgs" text;

alter table "public"."gen_questions" add column "is_exercise_question" boolean not null default false;

alter table "public"."gen_questions" add column "is_solved_example" boolean not null default false;

alter table "public"."qgen_generation_panes" drop column "total_questions_count";