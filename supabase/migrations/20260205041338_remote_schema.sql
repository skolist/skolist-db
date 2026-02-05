alter table "public"."qgen_generation_panes" add column "exercise_questions_count" smallint not null default '0'::smallint;

alter table "public"."qgen_generation_panes" add column "solved_examples_count" smallint not null default '0'::smallint;