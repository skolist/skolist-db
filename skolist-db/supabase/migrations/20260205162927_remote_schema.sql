alter table "public"."users" drop constraint "users_user_type_check";

alter table "public"."bank_questions" add column "chapter_id" uuid;

alter table "public"."qgen_generation_panes" alter column "exercise_questions_count" drop default;

alter table "public"."qgen_generation_panes" alter column "exercise_questions_count" drop not null;

alter table "public"."qgen_generation_panes" alter column "fill_in_the_blanks_count" drop default;

alter table "public"."qgen_generation_panes" alter column "long_answer_count" drop default;

alter table "public"."qgen_generation_panes" alter column "match_the_following_count" drop default;

alter table "public"."qgen_generation_panes" alter column "match_the_following_count" drop not null;

alter table "public"."qgen_generation_panes" alter column "mcq_count" drop default;

alter table "public"."qgen_generation_panes" alter column "msq_count" drop default;

alter table "public"."qgen_generation_panes" alter column "short_answer_count" drop default;

alter table "public"."qgen_generation_panes" alter column "solved_examples_count" drop default;

alter table "public"."qgen_generation_panes" alter column "solved_examples_count" drop not null;

alter table "public"."qgen_generation_panes" alter column "true_false_count" drop default;

alter table "public"."bank_questions" add constraint "bank_questions_chapter_id_fkey" FOREIGN KEY (chapter_id) REFERENCES public.chapters(id) not valid;

alter table "public"."bank_questions" validate constraint "bank_questions_chapter_id_fkey";

alter table "public"."users" add constraint "users_user_type_check" CHECK ((user_type = ANY (ARRAY['admin'::text, 'teacher'::text, 'student'::text, 'principal'::text, 'private_user'::text, 'skolist-admin'::text]))) not valid;

alter table "public"."users" validate constraint "users_user_type_check";



