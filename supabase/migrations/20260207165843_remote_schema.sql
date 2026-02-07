alter table "public"."bank_questions" alter column "hardness_level" drop default;

alter table "public"."bank_questions" alter column hardness_level type "public"."hardness_level_enum" using hardness_level::text::"public"."hardness_level_enum";

alter table "public"."bank_questions" alter column "hardness_level" set default null;

alter table "public"."bank_questions" alter column "hardness_level" set default 'easy'::public.hardness_level_enum;

alter table "public"."gen_question_versions" add column "match_the_following_columns" jsonb;
