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

CREATE TRIGGER objects_delete_delete_prefix AFTER DELETE ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();

CREATE TRIGGER objects_insert_create_prefix BEFORE INSERT ON storage.objects FOR EACH ROW EXECUTE FUNCTION storage.objects_insert_prefix_trigger();

CREATE TRIGGER objects_update_create_prefix BEFORE UPDATE ON storage.objects FOR EACH ROW WHEN (((new.name <> old.name) OR (new.bucket_id <> old.bucket_id))) EXECUTE FUNCTION storage.objects_update_prefix_trigger();

CREATE TRIGGER prefixes_create_hierarchy BEFORE INSERT ON storage.prefixes FOR EACH ROW WHEN ((pg_trigger_depth() < 1)) EXECUTE FUNCTION storage.prefixes_insert_trigger();

CREATE TRIGGER prefixes_delete_hierarchy AFTER DELETE ON storage.prefixes FOR EACH ROW EXECUTE FUNCTION storage.delete_prefix_hierarchy_trigger();


