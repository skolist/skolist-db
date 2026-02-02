


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "public";






CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."hardness_level_enum" AS ENUM (
    'easy',
    'medium',
    'hard'
);


ALTER TYPE "public"."hardness_level_enum" OWNER TO "postgres";


CREATE TYPE "public"."product_type_enum" AS ENUM (
    'qgen',
    'ai_tutor'
);


ALTER TYPE "public"."product_type_enum" OWNER TO "postgres";


CREATE TYPE "public"."question_type_enum" AS ENUM (
    'mcq4',
    'msq4',
    'short_answer',
    'true_or_false',
    'fill_in_the_blanks',
    'long_answer',
    'match_the_following'
);


ALTER TYPE "public"."question_type_enum" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."block_email_if_google_exists"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  already_has_google boolean;
begin
  -- Only check for email/password signups
  if new.raw_app_meta_data->>'provider' = 'email' then

    select exists (
      select 1
      from auth.users u
      where u.email = new.email
        and u.raw_app_meta_data->'providers' ? 'google'
    )
    into already_has_google;

    if already_has_google then
      -- Reject the email signup if the email is already used by Google
      raise exception
        'EMAIL_ALREADY_USED_WITH_GOOGLE'
        using
          errcode = 'P0001',
          hint = 'USE_GOOGLE_LOGIN';
    end if;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."block_email_if_google_exists"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."block_email_signup_if_google_exists"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  google_exists boolean;
begin
  -- only block EMAIL signups
  if new.app_metadata->>'provider' = 'email' then

    select exists (
      select 1
      from auth.users u
      where u.email = new.email
        and u.app_metadata->'providers' ? 'google'
    )
    into google_exists;

    if google_exists then
      raise exception
        'EMAIL_ALREADY_USED_WITH_GOOGLE'
        using
          errcode = 'P0001',
          hint = 'USE_GOOGLE_LOGIN';
    end if;

  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."block_email_signup_if_google_exists"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_qgen_draft_on_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_org record;
  v_user record;

  v_institute_name text;
  v_logo_url text;
begin
  -- Only for qgen activities
  if new.product_type <> 'qgen' then
    return new;
  end if;

  -- Fetch user
  select *
  into v_user
  from public.users
  where id = new.user_id;

  -- Fetch org if exists
  if v_user.org_id is not null then
    select *
    into v_org
    from public.orgs
    where id = v_user.org_id;
  end if;

  /*
    Institute name priority:
    1. org.header_line
    2. user_entered_school_name
    3. dummy fallback
  */
  v_institute_name :=
    coalesce(
      v_org.header_line,
      v_user.user_entered_school_name,
      'Example Institute'
    );

  /*
    Logo priority:
    1. org.logo_url
    2. user avatar (optional, if you want)
    3. null (frontend can show placeholder)
  */
  v_logo_url :=
    coalesce(
      v_org.logo_url,
      v_user.avatar_url,
      null
    );

  -- Create qgen draft
  insert into public.qgen_drafts (
    activity_id,
    institute_name,
    logo_url,
    paper_title
  )
  values (
    new.id,
    v_institute_name,
    v_logo_url,
    new.name
  )
  on conflict (activity_id) do nothing;

  return new;
end;
$$;


ALTER FUNCTION "public"."create_qgen_draft_on_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_qgen_generation_pane_on_new_activity"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
  v_org_id uuid;
  v_board_id uuid;
  v_school_class_id uuid;
  v_subject_id uuid;
begin
  -- Only for qgen activities
  if new.product_type <> 'qgen' then
    return new;
  end if;

  -- 1. Find org_id for the user who owns this activity
  --    (assuming new.user_id exists; adjust if different)
  select org_id into v_org_id
  from public.users
  where id = new.user_id;

  if v_org_id is null then
    -- can't infer anything, continue with defaults
    return new;
  end if;

  -- 2. Find board_id
  select board_id into v_board_id
  from public.orgs
  where id = v_org_id;

  if v_board_id is not null then
    -- 3. First available class in the board
    select id into v_school_class_id
    from public.school_classes
    where board_id = v_board_id
    order by created_at
    limit 1;

    if v_school_class_id is not null then
      -- 4. First available subject in that class
      select id into v_subject_id
      from public.subjects
      where school_class_id = v_school_class_id
      order by created_at
      limit 1;
    end if;
  end if;

  -- Create qgen draft
  insert into public.qgen_generation_panes (
    activity_id,
    school_class_id,
    subject_id
  )
  values (
    new.id,
    v_school_class_id,
    v_subject_id
  )
  on conflict (activity_id) do update
    set school_class_id = excluded.school_class_id,
        subject_id = excluded.subject_id;

  return new;
end;$$;


ALTER FUNCTION "public"."create_qgen_generation_pane_on_new_activity"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_draft_logo_on_activity_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  api_key text;
  project_url text := 'https://xgugcyguhzfevxvjdgbm.supabase.co';
  logo_path text;
  full_url text;
begin
  -- 1. Build path directly from activity_id
  logo_path := old.id || '/logo.png';

  -- 2. Fetch service role key from Vault
  select decrypted_secret
  into api_key
  from vault.decrypted_secrets
  where name = 'service_role_key'
  limit 1;

  if api_key is null then
    raise warning 'Delete logo failed: missing service role key';
    return old;
  end if;

  -- 3. Construct full delete URL
  full_url := project_url || '/storage/v1/object/draft_logo_bucket/' || logo_path;

  -- 4. Delete logo file
  perform net.http_delete(
    url := full_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || api_key,
      'apikey', api_key
    )
  );

  return old;
end;
$$;


ALTER FUNCTION "public"."delete_draft_logo_on_activity_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."delete_image_from_bucket"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'vault', 'net'
    AS $$
declare
  api_key text;
  project_url text;
  full_url text;
begin
  -- 1. Safety check
  if old.file_path is null then
    return old;
  end if;

  -- 2. SECURELY Retrieve Key from Vault
  -- We select the decrypted secret from the vault table
  select decrypted_secret into api_key 
  from vault.decrypted_secrets 
  where name = 'service_role_key' 
  limit 1;

  -- Safety Check: Stop if key is not found
  if api_key is null then
    raise warning 'Image deletion failed: service_role_key not found in Vault';
    return old;
  end if;

  -- 3. Construct URL (Use your specific project URL)
  project_url := 'https://fssxbvmkatrkejzsvwea.supabase.co'; 
  full_url := project_url || '/storage/v1/object/gen_images_bucket/' || old.file_path;

  -- 4. Perform Request
  perform net.http_delete(
    url := full_url,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || api_key,
      'apikey', api_key
    )
  );

  return old;
end;
$$;


ALTER FUNCTION "public"."delete_image_from_bucket"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gen_questions_insert_in_section"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
  insert_at smallint;
  target_section_pos smallint;
  draft_id uuid;
begin
  -- Act only when inserting INTO a draft section
  if (new.is_in_draft = true and new.qgen_draft_section_id is not null) then

    --------------------------------------------------------------------
    -- 0) Get the draft_id and the target section's relative position
    --------------------------------------------------------------------
    select id
    into draft_id
    from qgen_drafts
    where activity_id = new.activity_id;

    select position_in_draft into target_section_pos 
    from qgen_draft_sections 
    where id = new.qgen_draft_section_id;
    --------------------------------------------------------------------
    --- 1) Find the insertion point globally
    --------------------------------------------------------------------
    select coalesce(max(q.position_in_draft), 0) + 1
    into insert_at
    from gen_questions q
    join qgen_draft_sections s on q.qgen_draft_section_id = s.id
    where q.activity_id = new.activity_id
      and q.is_in_draft = true
      and s.position_in_draft <= target_section_pos;

    --------------------------------------------------------------------
    -- 2) Shift EVERY question that comes after this point
    --------------------------------------------------------------------
    update gen_questions
    set position_in_draft = position_in_draft + 1
    where activity_id = new.activity_id
      and is_in_draft = true
      and position_in_draft >= insert_at;

    -------------------------------------------------------------------
    -- 3) Assign the calculated global position
    new.position_in_draft := insert_at;
    ---------------------------------------------------------------
    -- 4) Bump the GLOBAL DRAFT COUNTER for consistency
    --------------------------------------------------------------------
    update qgen_drafts
    set max_position = max_position + 1
    where id = draft_id;

  end if;

  return new;
end;$$;


ALTER FUNCTION "public"."gen_questions_insert_in_section"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gen_questions_reorder_on_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
  draft_id uuid;
begin
  -- Only reorder if deleted row had a position
  if old.position_in_draft is not null then

    --------------------------------------------------------------------
    -- 0. Find the draft id for this activity
    --------------------------------------------------------------------
    select id
    into draft_id
    from qgen_drafts
    where activity_id = old.activity_id;

    --------------------------------------------------------------------
    -- 1. Lock all draft questions (to ensure deterministic shifting)
    --------------------------------------------------------------------
    perform 1
    from gen_questions
    where activity_id = old.activity_id
      and is_in_draft = true
    for update;

    --------------------------------------------------------------------
    -- 2. Shift all positions after the deleted one
    --------------------------------------------------------------------
    update gen_questions
    set position_in_draft = position_in_draft - 1
    where activity_id = old.activity_id
      and is_in_draft = true
      and position_in_draft > old.position_in_draft;

    --------------------------------------------------------------------
    -- 3. Decrement the global max_position ALWAYS
    --    Because list stays dense: 1..N → delete → 1..N-1
    --------------------------------------------------------------------
    update qgen_drafts
    set max_position = max_position - 1
    where id = draft_id;

  end if;

  return old;
end;$$;


ALTER FUNCTION "public"."gen_questions_reorder_on_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."gen_questions_reorder_on_exit_from_draft"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$declare
  draft_id uuid;
begin
  -- Only act when is_in_draft flips true → false
  if old.is_in_draft and not new.is_in_draft then

    --------------------------------------------------------------------
    -- 0. Find the draft
    --------------------------------------------------------------------
    select id
    into draft_id
    from qgen_drafts
    where activity_id = old.activity_id;

    --------------------------------------------------------------------
    -- 1. Lock all remaining draft questions
    --------------------------------------------------------------------
    perform 1
    from gen_questions
    where activity_id = old.activity_id
      and is_in_draft = true
    for update;

    --------------------------------------------------------------------
    -- 2. Shift positions of all items below the one being removed
    --------------------------------------------------------------------
    update gen_questions
    set position_in_draft = position_in_draft - 1
    where activity_id = old.activity_id
      and is_in_draft = true
      and position_in_draft > old.position_in_draft;

    --------------------------------------------------------------------
    -- 3. Decrement the global max_position ALWAYS (dense ordering)
    --------------------------------------------------------------------
    update qgen_drafts
    set max_position = max_position - 1
    where id = draft_id;

    --------------------------------------------------------------------
    -- 4. Remove draft metadata from the question
    --------------------------------------------------------------------
    new.position_in_draft := null;
    new.qgen_draft_section_id := null;

  end if;

  return new;
end;$$;


ALTER FUNCTION "public"."gen_questions_reorder_on_exit_from_draft"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_auth_user_created"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$BEGIN
  INSERT INTO public.users (
    id,
    email,
    phone_num,
    user_type,
    name,
    avatar_url,
    org_id
  )
  VALUES (
    NEW.id,
    NEW.email,
    NEW.phone,
    'private_user',
    NEW.raw_user_meta_data ->> 'name',
    NEW.raw_user_meta_data ->> 'avatar_url',
    '751434e6-0e95-4e09-8b78-1f8b1e05a94c'
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;$$;


ALTER FUNCTION "public"."handle_auth_user_created"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."insert_default_instructions"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  insert into qgen_draft_instructions_drafts_maps 
    ("qgen_draft_id", instruction_text)
  values
    (new.id, 'All questions are compulsory.'),
    (new.id, 'Read the questions carefully before answering.');

  return new;
end;
$$;


ALTER FUNCTION "public"."insert_default_instructions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."set_image_position"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if new.position is null then
    select coalesce(max(position), 0) + 1
    into new.position
    from gen_images
    where gen_question_id = new.gen_question_id;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."set_image_position"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_last_active"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  update public.users
  set last_active_at = new.last_sign_in_at
  where id = new.id;

  return new;
end;
$$;


ALTER FUNCTION "public"."sync_last_active"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_question_position_and_section_ids"("updates" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$BEGIN
    UPDATE public.gen_questions g
    SET 
        position_in_draft = d.position_in_draft,
        qgen_draft_section_id = d.qgen_draft_section_id,
        is_in_draft = true,
        updated_at = now()
    FROM jsonb_to_recordset(updates) AS d(
        id uuid, 
        position_in_draft smallint, 
        qgen_draft_section_id uuid
    )
    WHERE g.id = d.id;
END;$$;


ALTER FUNCTION "public"."update_question_position_and_section_ids"("updates" "jsonb") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."activities" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "name" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "product_type" "public"."product_type_enum" NOT NULL
);


ALTER TABLE "public"."activities" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."bank_questions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "subject_id" "uuid" NOT NULL,
    "reference" "text",
    "question_text" "text" NOT NULL,
    "answer_text" "text" NOT NULL,
    "figure" "text",
    "marks" smallint,
    "explanation" "text",
    "option1" "text",
    "option2" "text",
    "option3" "text",
    "option4" "text",
    "correct_mcq_option" smallint,
    "msq_option1_answer" boolean,
    "msq_option2_answer" boolean,
    "msq_option3_answer" boolean,
    "msq_option4_answer" boolean,
    "question_type" "public"."question_type_enum" NOT NULL,
    "hardness_level" "public"."hardness_level_enum"
);


ALTER TABLE "public"."bank_questions" OWNER TO "postgres";


COMMENT ON TABLE "public"."bank_questions" IS 'The question Bank (includes the solved example, pyqs, etc.)';



CREATE TABLE IF NOT EXISTS "public"."bank_questions_concepts_maps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "concept_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bank_question_id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "public"."bank_questions_concepts_maps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."boards" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."boards" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."chapters" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "subject_id" "uuid" NOT NULL,
    "position" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."chapters" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."concepts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "topic_id" "uuid" NOT NULL,
    "page_number" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "concepts_page_num_check" CHECK (("page_number" > 0))
);


ALTER TABLE "public"."concepts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."concepts_activities_maps" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "concept_id" "uuid" DEFAULT "gen_random_uuid"(),
    "activity_id" "uuid" DEFAULT "gen_random_uuid"()
);


ALTER TABLE "public"."concepts_activities_maps" OWNER TO "postgres";


ALTER TABLE "public"."concepts_activities_maps" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."concepts_activities_maps_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."gen_artifacts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "source_url" "text" NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."gen_artifacts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gen_images" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "svg_string" "text",
    "img_url" "text",
    "gen_question_id" "uuid" DEFAULT "gen_random_uuid"(),
    "position" smallint,
    "file_path" "text"
);


ALTER TABLE "public"."gen_images" OWNER TO "postgres";


COMMENT ON TABLE "public"."gen_images" IS 'This table stores the images relevant to a question in the form of foreign key to the question and a image. Image can be stored in two forms here, either as object in the storage and then adding its image url to the img_url column, or directly storing the SVG format in the svg_string column. Positions start from 1,2,3 ...';



CREATE TABLE IF NOT EXISTS "public"."gen_question_versions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "marks" smallint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "answer_text" "text" NOT NULL,
    "question_text" "text",
    "explanation" "text",
    "option1" "text",
    "option2" "text",
    "option3" "text",
    "option4" "text",
    "correct_mcq_option" smallint,
    "msq_option1_answer" boolean,
    "msq_option2_answer" boolean,
    "msq_option3_answer" boolean,
    "msq_option4_answer" boolean,
    "question_type" "public"."question_type_enum" NOT NULL,
    "hardness_level" "public"."hardness_level_enum" NOT NULL,
    "gen_question_id" "uuid",
    CONSTRAINT "gen_question_versions_correct_mcq_option_check" CHECK (("correct_mcq_option" = ANY (ARRAY[1, 2, 3, 4]))),
    CONSTRAINT "gen_question_versions_marks_check" CHECK (("marks" >= 0))
);


ALTER TABLE "public"."gen_question_versions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."gen_questions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "is_in_draft" boolean DEFAULT false NOT NULL,
    "marks" smallint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "answer_text" "text" NOT NULL,
    "question_text" "text",
    "explanation" "text",
    "option1" "text",
    "option2" "text",
    "option3" "text",
    "option4" "text",
    "correct_mcq_option" smallint,
    "msq_option1_answer" boolean,
    "msq_option2_answer" boolean,
    "msq_option3_answer" boolean,
    "msq_option4_answer" boolean,
    "qgen_draft_section_id" "uuid",
    "position_in_draft" smallint,
    "is_page_break_below" boolean DEFAULT false NOT NULL,
    "question_type" "public"."question_type_enum" NOT NULL,
    "hardness_level" "public"."hardness_level_enum" NOT NULL,
    "match_the_following_columns" "jsonb",
    CONSTRAINT "gen_questions_correct_mcq_option_check" CHECK (("correct_mcq_option" = ANY (ARRAY[1, 2, 3, 4]))),
    CONSTRAINT "gen_questions_marks_check" CHECK (("marks" >= 0)),
    CONSTRAINT "gen_questions_position_in_draft_check" CHECK (("position_in_draft" >= 1))
);


ALTER TABLE "public"."gen_questions" OWNER TO "postgres";


COMMENT ON COLUMN "public"."gen_questions"."answer_text" IS 'Answer for the Generated question. Not For MCQs and MSQs';



COMMENT ON COLUMN "public"."gen_questions"."question_text" IS 'Actual Question';



COMMENT ON COLUMN "public"."gen_questions"."explanation" IS 'explanation for the question and answer';



COMMENT ON COLUMN "public"."gen_questions"."option1" IS 'For MCQ or MSQs';



COMMENT ON COLUMN "public"."gen_questions"."option2" IS 'For MCQs or MSQs';



COMMENT ON COLUMN "public"."gen_questions"."option3" IS 'For MCQs or MSQs';



COMMENT ON COLUMN "public"."gen_questions"."option4" IS 'For MCQs or MSQs';



COMMENT ON COLUMN "public"."gen_questions"."correct_mcq_option" IS 'can be 1 or 2 or 3 or 4';



COMMENT ON COLUMN "public"."gen_questions"."msq_option1_answer" IS 'Describes if the option is correct or incorrect';



COMMENT ON COLUMN "public"."gen_questions"."msq_option2_answer" IS 'Describes if the option is correct or incorrect';



COMMENT ON COLUMN "public"."gen_questions"."msq_option3_answer" IS 'Describes if the option is correct or incorrect';



COMMENT ON COLUMN "public"."gen_questions"."msq_option4_answer" IS 'Describes if the option is correct or incorrect';



COMMENT ON COLUMN "public"."gen_questions"."qgen_draft_section_id" IS 'The id of the section to which this question belongs to if, this is in draft';



COMMENT ON COLUMN "public"."gen_questions"."position_in_draft" IS 'Position of the question in the section in the draft, if this question belongs to a draft';



COMMENT ON COLUMN "public"."gen_questions"."is_page_break_below" IS 'If the question is in a draft, then this variable will tell if to add a page break after this question in the pdf being generated';



CREATE TABLE IF NOT EXISTS "public"."gen_questions_concepts_maps" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "gen_question_id" "uuid" NOT NULL,
    "concept_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."gen_questions_concepts_maps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."generation_pane_concepts_maps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "concept_id" "uuid" NOT NULL,
    "qgen_generation_pane_id" "uuid" NOT NULL
);


ALTER TABLE "public"."generation_pane_concepts_maps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."orgs" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "email" "text" NOT NULL,
    "logo_url" "text",
    "org_type" "text",
    "phone_num" "text" NOT NULL,
    "address" "text",
    "header_line" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "board_id" "uuid",
    CONSTRAINT "orgs_org_type_check" CHECK (("org_type" = ANY (ARRAY['institution'::"text", 'school'::"text", 'tuition'::"text"])))
);


ALTER TABLE "public"."orgs" OWNER TO "postgres";


COMMENT ON COLUMN "public"."orgs"."board_id" IS 'To which board the organisation belongs to';



CREATE TABLE IF NOT EXISTS "public"."phonenum_otps" (
    "phone_number" "text" NOT NULL,
    "otp" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."phonenum_otps" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."qgen_draft_instructions_drafts_maps" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "instruction_text" "text",
    "qgen_draft_id" "uuid" NOT NULL
);


ALTER TABLE "public"."qgen_draft_instructions_drafts_maps" OWNER TO "postgres";


COMMENT ON TABLE "public"."qgen_draft_instructions_drafts_maps" IS 'Stores instructions for paper as a relation with teacher / user/';



CREATE TABLE IF NOT EXISTS "public"."qgen_draft_sections" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "qgen_draft_id" "uuid" DEFAULT "gen_random_uuid"(),
    "section_name" "text",
    "position_in_draft" smallint DEFAULT '1'::smallint NOT NULL,
    CONSTRAINT "qgen_draft_sections_position_in_draft_check" CHECK (("position_in_draft" >= 1))
);


ALTER TABLE "public"."qgen_draft_sections" OWNER TO "postgres";


COMMENT ON TABLE "public"."qgen_draft_sections" IS 'Sections in the draft  of the paper to be generated';



COMMENT ON COLUMN "public"."qgen_draft_sections"."position_in_draft" IS 'The position of the section in the draft of the paper to be generated as PDF';



CREATE TABLE IF NOT EXISTS "public"."qgen_drafts" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "activity_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "paper_datetime" timestamp without time zone,
    "paper_duration" time without time zone,
    "maximum_marks" smallint,
    "institute_name" "text",
    "paper_title" "text",
    "paper_subtitle" "text",
    "logo_url" "text",
    "subject_name" "text",
    "school_class_name" "text",
    "max_position" smallint DEFAULT '0'::smallint
);


ALTER TABLE "public"."qgen_drafts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."qgen_drafts"."paper_datetime" IS 'The Date and time of examination to be shown on the generated PDF';



COMMENT ON COLUMN "public"."qgen_drafts"."paper_duration" IS 'Duration of the paper to be shown on the generated PDF';



COMMENT ON COLUMN "public"."qgen_drafts"."maximum_marks" IS 'Maximum / Total Marks to be shown on the generated paper PDF';



COMMENT ON COLUMN "public"."qgen_drafts"."institute_name" IS 'Institute / School Name to be shown on the top of the generated pdf of the paper';



COMMENT ON COLUMN "public"."qgen_drafts"."paper_title" IS 'Title of the Paper to be shown in the generated PDF';



COMMENT ON COLUMN "public"."qgen_drafts"."paper_subtitle" IS 'Subtitle of the paper to be shown in the generated pdf';



COMMENT ON COLUMN "public"."qgen_drafts"."logo_url" IS 'URL of the logo to be shown on the generated question paper pdf';



CREATE TABLE IF NOT EXISTS "public"."qgen_generation_panes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "school_class_id" "uuid",
    "subject_id" "uuid",
    "total_questions_count" smallint DEFAULT '12'::smallint,
    "total_marks_count" smallint DEFAULT '30'::smallint,
    "total_time_count" smallint DEFAULT '60'::smallint,
    "mcq_count" smallint DEFAULT '2'::smallint,
    "msq_count" smallint DEFAULT '2'::smallint,
    "short_answer_count" smallint DEFAULT '2'::smallint,
    "long_answer_count" smallint DEFAULT '2'::smallint,
    "true_false_count" smallint DEFAULT '2'::smallint,
    "fill_in_the_blanks_count" smallint DEFAULT '2'::smallint,
    "difficulty_level_easy_count" smallint DEFAULT '50'::smallint,
    "difficulty_level_medium_count" smallint DEFAULT '30'::smallint,
    "difficulty_level_hard_count" smallint DEFAULT '20'::smallint,
    "custom_instructions" "text",
    "updated_at" timestamp with time zone,
    "activity_id" "uuid" DEFAULT "gen_random_uuid"(),
    "match_the_following_count" smallint DEFAULT '2'::smallint NOT NULL,
    CONSTRAINT "qgen_generation_panes_match_the_following_count_check" CHECK (("match_the_following_count" >= 0))
);


ALTER TABLE "public"."qgen_generation_panes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."school_classes" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "board_id" "uuid" NOT NULL,
    "position" integer NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "classes_position_check" CHECK (("position" >= 0))
);


ALTER TABLE "public"."school_classes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."subjects" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "school_class_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."subjects" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."topics" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "chapter_id" "uuid" NOT NULL,
    "position" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."topics" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "user_type" "text" NOT NULL,
    "email" "text",
    "phone_num" "text",
    "credits" smallint DEFAULT '1000'::smallint NOT NULL,
    "avatar_url" "text",
    "org_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text",
    "account_status" "text" DEFAULT 'active'::"text" NOT NULL,
    "last_active_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_entered_school_name" "text",
    "user_entered_school_address" "text",
    "user_entered_school_board" "text",
    CONSTRAINT "users_account_status_check" CHECK (("account_status" = ANY (ARRAY['active'::"text", 'inactive'::"text", 'disabled'::"text"]))),
    CONSTRAINT "users_check" CHECK ((("email" IS NOT NULL) OR ("phone_num" IS NOT NULL))),
    CONSTRAINT "users_name_check" CHECK (("length"("name") <= 50)),
    CONSTRAINT "users_user_type_check" CHECK (("user_type" = ANY (ARRAY['admin'::"text", 'teacher'::"text", 'student'::"text", 'principal'::"text", 'private_user'::"text"])))
);


ALTER TABLE "public"."users" OWNER TO "postgres";


COMMENT ON COLUMN "public"."users"."name" IS 'The Full Name of The User';



COMMENT ON COLUMN "public"."users"."account_status" IS 'Is account active or disabled or inactive or deactivated etc.';



COMMENT ON COLUMN "public"."users"."last_active_at" IS 'To track user Churn';



COMMENT ON COLUMN "public"."users"."user_entered_school_name" IS 'The School Name which the User have Entered, for direct login users, not associated with organisation initially';



COMMENT ON COLUMN "public"."users"."user_entered_school_address" IS 'The School Address which user manually enters, for thus who are not associated with any organisation';



COMMENT ON COLUMN "public"."users"."user_entered_school_board" IS 'The Board which user enters manually, for thus users who are not part of any organisation, and doing a signup via website directly.';



ALTER TABLE ONLY "public"."activities"
    ADD CONSTRAINT "activities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bank_questions_concepts_maps"
    ADD CONSTRAINT "bank_questions_concepts_maps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bank_questions"
    ADD CONSTRAINT "bank_questions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."boards"
    ADD CONSTRAINT "boards_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."boards"
    ADD CONSTRAINT "boards_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chapters"
    ADD CONSTRAINT "chapters_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."chapters"
    ADD CONSTRAINT "chapters_subject_id_name_key" UNIQUE ("subject_id", "name");



ALTER TABLE ONLY "public"."chapters"
    ADD CONSTRAINT "chapters_subject_id_position_key" UNIQUE ("subject_id", "position");



ALTER TABLE ONLY "public"."school_classes"
    ADD CONSTRAINT "classes_board_id_name_key" UNIQUE ("board_id", "name");



ALTER TABLE ONLY "public"."school_classes"
    ADD CONSTRAINT "classes_board_id_position_key" UNIQUE ("board_id", "position");



ALTER TABLE ONLY "public"."school_classes"
    ADD CONSTRAINT "classes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."concepts_activities_maps"
    ADD CONSTRAINT "concepts_activities_maps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."concepts"
    ADD CONSTRAINT "concepts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."concepts"
    ADD CONSTRAINT "concepts_topic_id_name_key" UNIQUE ("topic_id", "name");



ALTER TABLE ONLY "public"."gen_artifacts"
    ADD CONSTRAINT "gen_artifacts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gen_images"
    ADD CONSTRAINT "gen_images_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gen_question_versions"
    ADD CONSTRAINT "gen_question_versions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gen_questions_concepts_maps"
    ADD CONSTRAINT "gen_questions_concepts_maps_gen_question_id_concept_id_key" UNIQUE ("gen_question_id", "concept_id");



ALTER TABLE ONLY "public"."gen_questions_concepts_maps"
    ADD CONSTRAINT "gen_questions_concepts_maps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."gen_questions"
    ADD CONSTRAINT "gen_questions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."generation_pane_concepts_maps"
    ADD CONSTRAINT "generation_pane_concepts_maps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_phone_num_key" UNIQUE ("phone_num");



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."phonenum_otps"
    ADD CONSTRAINT "phonenum_otps_pkey" PRIMARY KEY ("phone_number");



ALTER TABLE ONLY "public"."qgen_draft_instructions_drafts_maps"
    ADD CONSTRAINT "qgen_draft_instructions_maps_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."qgen_draft_sections"
    ADD CONSTRAINT "qgen_draft_sections_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."qgen_drafts"
    ADD CONSTRAINT "qgen_drafts_activity_id_key" UNIQUE ("activity_id");



ALTER TABLE ONLY "public"."qgen_drafts"
    ADD CONSTRAINT "qgen_drafts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."qgen_generation_panes"
    ADD CONSTRAINT "qgen_generation_panes_activity_id_key" UNIQUE ("activity_id");



ALTER TABLE ONLY "public"."qgen_generation_panes"
    ADD CONSTRAINT "qgen_generation_panes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."subjects"
    ADD CONSTRAINT "subjects_class_id_name_key" UNIQUE ("school_class_id", "name");



ALTER TABLE ONLY "public"."subjects"
    ADD CONSTRAINT "subjects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_chapter_id_name_key" UNIQUE ("chapter_id", "name");



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_chapter_id_position_key" UNIQUE ("chapter_id", "position");



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."concepts_activities_maps"
    ADD CONSTRAINT "unique_concept_activity" UNIQUE ("concept_id", "activity_id");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_phone_num_key" UNIQUE ("phone_num");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE INDEX "idx_activities_user_id" ON "public"."activities" USING "btree" ("user_id");



CREATE INDEX "idx_chapters_subject_id" ON "public"."chapters" USING "btree" ("subject_id");



CREATE INDEX "idx_classes_board_id" ON "public"."school_classes" USING "btree" ("board_id");



CREATE INDEX "idx_concepts_topic_id" ON "public"."concepts" USING "btree" ("topic_id");



CREATE INDEX "idx_gen_artifacts_activity_id" ON "public"."gen_artifacts" USING "btree" ("activity_id");



CREATE INDEX "idx_gen_questions_activity_draft" ON "public"."gen_questions" USING "btree" ("activity_id", "is_in_draft");



CREATE INDEX "idx_gen_questions_concepts_maps_concept_id" ON "public"."gen_questions_concepts_maps" USING "btree" ("concept_id");



CREATE INDEX "idx_gen_questions_concepts_maps_gen_question_id" ON "public"."gen_questions_concepts_maps" USING "btree" ("gen_question_id");



CREATE INDEX "idx_qgen_drafts_activity_id" ON "public"."qgen_drafts" USING "btree" ("activity_id");



CREATE INDEX "idx_subjects_class_id" ON "public"."subjects" USING "btree" ("school_class_id");



CREATE INDEX "idx_topics_chapter_id" ON "public"."topics" USING "btree" ("chapter_id");



CREATE INDEX "idx_users_org_id" ON "public"."users" USING "btree" ("org_id");



CREATE UNIQUE INDEX "users_email_lower_idx" ON "public"."users" USING "btree" ("lower"("email")) WHERE ("email" IS NOT NULL);



CREATE OR REPLACE TRIGGER "delete_image_from_bucket" AFTER DELETE ON "public"."gen_images" FOR EACH ROW EXECUTE FUNCTION "public"."delete_image_from_bucket"();



CREATE OR REPLACE TRIGGER "on_qgen_draft_created" AFTER INSERT ON "public"."qgen_drafts" FOR EACH ROW EXECUTE FUNCTION "public"."insert_default_instructions"();



CREATE OR REPLACE TRIGGER "trg_create_qgen_draft" AFTER INSERT ON "public"."activities" FOR EACH ROW EXECUTE FUNCTION "public"."create_qgen_draft_on_activity"();



CREATE OR REPLACE TRIGGER "trg_create_qgen_generation_pane" AFTER INSERT ON "public"."activities" FOR EACH ROW EXECUTE FUNCTION "public"."create_qgen_generation_pane_on_new_activity"();



CREATE OR REPLACE TRIGGER "trg_delete_draft_logo" AFTER DELETE ON "public"."activities" FOR EACH ROW EXECUTE FUNCTION "public"."delete_draft_logo_on_activity_delete"();



CREATE OR REPLACE TRIGGER "trg_gen_questions_insert_in_section" BEFORE INSERT ON "public"."gen_questions" FOR EACH ROW EXECUTE FUNCTION "public"."gen_questions_insert_in_section"();



CREATE OR REPLACE TRIGGER "trg_gen_questions_reorder_on_delete" AFTER DELETE ON "public"."gen_questions" FOR EACH ROW EXECUTE FUNCTION "public"."gen_questions_reorder_on_delete"();



CREATE OR REPLACE TRIGGER "trg_gen_questions_reorder_on_exit_from_draft" BEFORE UPDATE ON "public"."gen_questions" FOR EACH ROW EXECUTE FUNCTION "public"."gen_questions_reorder_on_exit_from_draft"();



CREATE OR REPLACE TRIGGER "trg_set_position" BEFORE INSERT ON "public"."gen_images" FOR EACH ROW EXECUTE FUNCTION "public"."set_image_position"();



ALTER TABLE ONLY "public"."activities"
    ADD CONSTRAINT "activities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bank_questions_concepts_maps"
    ADD CONSTRAINT "bank_questions_concepts_maps_bank_question_id_fkey" FOREIGN KEY ("bank_question_id") REFERENCES "public"."bank_questions"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bank_questions_concepts_maps"
    ADD CONSTRAINT "bank_questions_concepts_maps_concept_id_fkey" FOREIGN KEY ("concept_id") REFERENCES "public"."concepts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bank_questions"
    ADD CONSTRAINT "bank_questions_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "public"."subjects"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."chapters"
    ADD CONSTRAINT "chapters_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "public"."subjects"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."school_classes"
    ADD CONSTRAINT "classes_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "public"."boards"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."concepts_activities_maps"
    ADD CONSTRAINT "concepts_activities_maps_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."concepts_activities_maps"
    ADD CONSTRAINT "concepts_activities_maps_concept_id_fkey" FOREIGN KEY ("concept_id") REFERENCES "public"."concepts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."concepts"
    ADD CONSTRAINT "concepts_topic_id_fkey" FOREIGN KEY ("topic_id") REFERENCES "public"."topics"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_artifacts"
    ADD CONSTRAINT "gen_artifacts_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_images"
    ADD CONSTRAINT "gen_images_gen_question_id_fkey" FOREIGN KEY ("gen_question_id") REFERENCES "public"."gen_questions"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_question_versions"
    ADD CONSTRAINT "gen_question_versions_gen_question_id_fkey" FOREIGN KEY ("gen_question_id") REFERENCES "public"."gen_questions"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_questions"
    ADD CONSTRAINT "gen_questions_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_questions_concepts_maps"
    ADD CONSTRAINT "gen_questions_concepts_maps_concept_id_fkey" FOREIGN KEY ("concept_id") REFERENCES "public"."concepts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_questions_concepts_maps"
    ADD CONSTRAINT "gen_questions_concepts_maps_gen_question_id_fkey" FOREIGN KEY ("gen_question_id") REFERENCES "public"."gen_questions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."gen_questions"
    ADD CONSTRAINT "gen_questions_qgen_draft_section_id_fkey" FOREIGN KEY ("qgen_draft_section_id") REFERENCES "public"."qgen_draft_sections"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."generation_pane_concepts_maps"
    ADD CONSTRAINT "generation_pane_concepts_maps_concept_id_fkey" FOREIGN KEY ("concept_id") REFERENCES "public"."concepts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."generation_pane_concepts_maps"
    ADD CONSTRAINT "generation_pane_concepts_maps_qgen_generation_pane_id_fkey" FOREIGN KEY ("qgen_generation_pane_id") REFERENCES "public"."qgen_generation_panes"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."orgs"
    ADD CONSTRAINT "orgs_board_id_fkey" FOREIGN KEY ("board_id") REFERENCES "public"."boards"("id");



ALTER TABLE ONLY "public"."qgen_draft_instructions_drafts_maps"
    ADD CONSTRAINT "qgen_draft_instructions_drafts_maps_qgen_draft_id_fkey" FOREIGN KEY ("qgen_draft_id") REFERENCES "public"."qgen_drafts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."qgen_draft_sections"
    ADD CONSTRAINT "qgen_draft_sections_qgen_draft_id_fkey" FOREIGN KEY ("qgen_draft_id") REFERENCES "public"."qgen_drafts"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."qgen_drafts"
    ADD CONSTRAINT "qgen_drafts_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."qgen_generation_panes"
    ADD CONSTRAINT "qgen_generation_panes_activity_id_fkey" FOREIGN KEY ("activity_id") REFERENCES "public"."activities"("id") ON UPDATE CASCADE ON DELETE CASCADE;



ALTER TABLE ONLY "public"."qgen_generation_panes"
    ADD CONSTRAINT "qgen_generation_panes_school_class_id_fkey" FOREIGN KEY ("school_class_id") REFERENCES "public"."school_classes"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."qgen_generation_panes"
    ADD CONSTRAINT "qgen_generation_panes_subject_id_fkey" FOREIGN KEY ("subject_id") REFERENCES "public"."subjects"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."subjects"
    ADD CONSTRAINT "subjects_school_class_id_fkey" FOREIGN KEY ("school_class_id") REFERENCES "public"."school_classes"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."topics"
    ADD CONSTRAINT "topics_chapter_id_fkey" FOREIGN KEY ("chapter_id") REFERENCES "public"."chapters"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_org_id_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE SET NULL;



CREATE POLICY "Deny public access" ON "public"."phonenum_otps" TO "authenticated", "anon" USING (false);



CREATE POLICY "Enable all access for service_role" ON "public"."phonenum_otps" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."activities" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "activities_owner_all" ON "public"."activities" TO "authenticated" USING (("user_id" = "auth"."uid"())) WITH CHECK (("user_id" = "auth"."uid"()));



CREATE POLICY "activity_owner_all" ON "public"."concepts_activities_maps" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "concepts_activities_maps"."activity_id") AND ("a"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "concepts_activities_maps"."activity_id") AND ("a"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."gen_artifacts" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "gen_artifacts"."activity_id") AND ("a"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "gen_artifacts"."activity_id") AND ("a"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."gen_images" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."gen_questions" "gq"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "gq"."activity_id")))
  WHERE (("gq"."id" = "gen_images"."gen_question_id") AND ("ac"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."gen_questions" "gq"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "gq"."activity_id")))
  WHERE (("gq"."id" = "gen_images"."gen_question_id") AND ("ac"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."gen_questions" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "gen_questions"."activity_id") AND ("a"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "gen_questions"."activity_id") AND ("a"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."gen_questions_concepts_maps" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."gen_questions" "gq"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "gq"."activity_id")))
  WHERE (("gq"."id" = "gen_questions_concepts_maps"."gen_question_id") AND ("ac"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."gen_questions" "gq"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "gq"."activity_id")))
  WHERE (("gq"."id" = "gen_questions_concepts_maps"."gen_question_id") AND ("ac"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."generation_pane_concepts_maps" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."qgen_generation_panes" "qgp"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "qgp"."activity_id")))
  WHERE (("qgp"."id" = "generation_pane_concepts_maps"."qgen_generation_pane_id") AND ("ac"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."qgen_generation_panes" "qgp"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "qgp"."activity_id")))
  WHERE (("qgp"."id" = "generation_pane_concepts_maps"."qgen_generation_pane_id") AND ("ac"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."qgen_draft_instructions_drafts_maps" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."qgen_drafts" "d"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "d"."activity_id")))
  WHERE (("d"."id" = "qgen_draft_instructions_drafts_maps"."qgen_draft_id") AND ("ac"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."qgen_drafts" "d"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "d"."activity_id")))
  WHERE (("d"."id" = "qgen_draft_instructions_drafts_maps"."qgen_draft_id") AND ("ac"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."qgen_draft_sections" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."qgen_drafts" "d"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "d"."activity_id")))
  WHERE (("d"."id" = "qgen_draft_sections"."qgen_draft_id") AND ("ac"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."qgen_drafts" "d"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "d"."activity_id")))
  WHERE (("d"."id" = "qgen_draft_sections"."qgen_draft_id") AND ("ac"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."qgen_drafts" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "qgen_drafts"."activity_id") AND ("a"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "qgen_drafts"."activity_id") AND ("a"."user_id" = "auth"."uid"())))));



CREATE POLICY "activity_owner_all" ON "public"."qgen_generation_panes" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "qgen_generation_panes"."activity_id") AND ("a"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."activities" "a"
  WHERE (("a"."id" = "qgen_generation_panes"."activity_id") AND ("a"."user_id" = "auth"."uid"())))));



ALTER TABLE "public"."bank_questions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."bank_questions_concepts_maps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."boards" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."chapters" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."concepts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."concepts_activities_maps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gen_artifacts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gen_images" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gen_question_versions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gen_questions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."gen_questions_concepts_maps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."generation_pane_concepts_maps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."orgs" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."phonenum_otps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."qgen_draft_instructions_drafts_maps" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."qgen_draft_sections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."qgen_drafts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."qgen_generation_panes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read_access_all" ON "public"."boards" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_access_all" ON "public"."chapters" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_access_all" ON "public"."concepts" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_access_all" ON "public"."school_classes" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_access_all" ON "public"."subjects" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_access_all" ON "public"."topics" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "read_org_by_user" ON "public"."orgs" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."org_id" = "orgs"."id")))));



ALTER TABLE "public"."school_classes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "service_role_all" ON "public"."bank_questions" TO "service_role" USING (true) WITH CHECK (true);



CREATE POLICY "service_role_all" ON "public"."bank_questions_concepts_maps" TO "service_role" USING (true) WITH CHECK (true);



ALTER TABLE "public"."subjects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."topics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_self_read" ON "public"."users" FOR SELECT TO "authenticated" USING (("id" = "auth"."uid"()));



CREATE POLICY "users_self_update" ON "public"."users" FOR UPDATE USING (("id" = "auth"."uid"()));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."activities";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."concepts_activities_maps";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."gen_artifacts";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."gen_images";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."gen_questions";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."gen_questions_concepts_maps";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."generation_pane_concepts_maps";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."qgen_draft_instructions_drafts_maps";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."qgen_draft_sections";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."qgen_drafts";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."qgen_generation_panes";



ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."users";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";




























































































































































GRANT ALL ON FUNCTION "public"."block_email_if_google_exists"() TO "anon";
GRANT ALL ON FUNCTION "public"."block_email_if_google_exists"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."block_email_if_google_exists"() TO "service_role";



GRANT ALL ON FUNCTION "public"."block_email_signup_if_google_exists"() TO "anon";
GRANT ALL ON FUNCTION "public"."block_email_signup_if_google_exists"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."block_email_signup_if_google_exists"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_qgen_draft_on_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_qgen_draft_on_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_qgen_draft_on_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."create_qgen_generation_pane_on_new_activity"() TO "anon";
GRANT ALL ON FUNCTION "public"."create_qgen_generation_pane_on_new_activity"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."create_qgen_generation_pane_on_new_activity"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_draft_logo_on_activity_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_draft_logo_on_activity_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_draft_logo_on_activity_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."delete_image_from_bucket"() TO "anon";
GRANT ALL ON FUNCTION "public"."delete_image_from_bucket"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."delete_image_from_bucket"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gen_questions_insert_in_section"() TO "anon";
GRANT ALL ON FUNCTION "public"."gen_questions_insert_in_section"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gen_questions_insert_in_section"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gen_questions_reorder_on_delete"() TO "anon";
GRANT ALL ON FUNCTION "public"."gen_questions_reorder_on_delete"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gen_questions_reorder_on_delete"() TO "service_role";



GRANT ALL ON FUNCTION "public"."gen_questions_reorder_on_exit_from_draft"() TO "anon";
GRANT ALL ON FUNCTION "public"."gen_questions_reorder_on_exit_from_draft"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."gen_questions_reorder_on_exit_from_draft"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_auth_user_created"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_auth_user_created"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_auth_user_created"() TO "service_role";



GRANT ALL ON FUNCTION "public"."insert_default_instructions"() TO "anon";
GRANT ALL ON FUNCTION "public"."insert_default_instructions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."insert_default_instructions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."set_image_position"() TO "anon";
GRANT ALL ON FUNCTION "public"."set_image_position"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."set_image_position"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_last_active"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_last_active"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_last_active"() TO "service_role";



GRANT ALL ON FUNCTION "public"."update_question_position_and_section_ids"("updates" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "public"."update_question_position_and_section_ids"("updates" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_question_position_and_section_ids"("updates" "jsonb") TO "service_role";


















GRANT ALL ON TABLE "public"."activities" TO "anon";
GRANT ALL ON TABLE "public"."activities" TO "authenticated";
GRANT ALL ON TABLE "public"."activities" TO "service_role";



GRANT ALL ON TABLE "public"."bank_questions" TO "anon";
GRANT ALL ON TABLE "public"."bank_questions" TO "authenticated";
GRANT ALL ON TABLE "public"."bank_questions" TO "service_role";



GRANT ALL ON TABLE "public"."bank_questions_concepts_maps" TO "anon";
GRANT ALL ON TABLE "public"."bank_questions_concepts_maps" TO "authenticated";
GRANT ALL ON TABLE "public"."bank_questions_concepts_maps" TO "service_role";



GRANT ALL ON TABLE "public"."boards" TO "anon";
GRANT ALL ON TABLE "public"."boards" TO "authenticated";
GRANT ALL ON TABLE "public"."boards" TO "service_role";



GRANT ALL ON TABLE "public"."chapters" TO "anon";
GRANT ALL ON TABLE "public"."chapters" TO "authenticated";
GRANT ALL ON TABLE "public"."chapters" TO "service_role";



GRANT ALL ON TABLE "public"."concepts" TO "anon";
GRANT ALL ON TABLE "public"."concepts" TO "authenticated";
GRANT ALL ON TABLE "public"."concepts" TO "service_role";



GRANT ALL ON TABLE "public"."concepts_activities_maps" TO "anon";
GRANT ALL ON TABLE "public"."concepts_activities_maps" TO "authenticated";
GRANT ALL ON TABLE "public"."concepts_activities_maps" TO "service_role";



GRANT ALL ON SEQUENCE "public"."concepts_activities_maps_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."concepts_activities_maps_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."concepts_activities_maps_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."gen_artifacts" TO "anon";
GRANT ALL ON TABLE "public"."gen_artifacts" TO "authenticated";
GRANT ALL ON TABLE "public"."gen_artifacts" TO "service_role";



GRANT ALL ON TABLE "public"."gen_images" TO "anon";
GRANT ALL ON TABLE "public"."gen_images" TO "authenticated";
GRANT ALL ON TABLE "public"."gen_images" TO "service_role";



GRANT ALL ON TABLE "public"."gen_question_versions" TO "anon";
GRANT ALL ON TABLE "public"."gen_question_versions" TO "authenticated";
GRANT ALL ON TABLE "public"."gen_question_versions" TO "service_role";



GRANT ALL ON TABLE "public"."gen_questions" TO "anon";
GRANT ALL ON TABLE "public"."gen_questions" TO "authenticated";
GRANT ALL ON TABLE "public"."gen_questions" TO "service_role";



GRANT ALL ON TABLE "public"."gen_questions_concepts_maps" TO "anon";
GRANT ALL ON TABLE "public"."gen_questions_concepts_maps" TO "authenticated";
GRANT ALL ON TABLE "public"."gen_questions_concepts_maps" TO "service_role";



GRANT ALL ON TABLE "public"."generation_pane_concepts_maps" TO "anon";
GRANT ALL ON TABLE "public"."generation_pane_concepts_maps" TO "authenticated";
GRANT ALL ON TABLE "public"."generation_pane_concepts_maps" TO "service_role";



GRANT ALL ON TABLE "public"."orgs" TO "anon";
GRANT ALL ON TABLE "public"."orgs" TO "authenticated";
GRANT ALL ON TABLE "public"."orgs" TO "service_role";



GRANT ALL ON TABLE "public"."phonenum_otps" TO "anon";
GRANT ALL ON TABLE "public"."phonenum_otps" TO "authenticated";
GRANT ALL ON TABLE "public"."phonenum_otps" TO "service_role";



GRANT ALL ON TABLE "public"."qgen_draft_instructions_drafts_maps" TO "anon";
GRANT ALL ON TABLE "public"."qgen_draft_instructions_drafts_maps" TO "authenticated";
GRANT ALL ON TABLE "public"."qgen_draft_instructions_drafts_maps" TO "service_role";



GRANT ALL ON TABLE "public"."qgen_draft_sections" TO "anon";
GRANT ALL ON TABLE "public"."qgen_draft_sections" TO "authenticated";
GRANT ALL ON TABLE "public"."qgen_draft_sections" TO "service_role";



GRANT ALL ON TABLE "public"."qgen_drafts" TO "anon";
GRANT ALL ON TABLE "public"."qgen_drafts" TO "authenticated";
GRANT ALL ON TABLE "public"."qgen_drafts" TO "service_role";



GRANT ALL ON TABLE "public"."qgen_generation_panes" TO "anon";
GRANT ALL ON TABLE "public"."qgen_generation_panes" TO "authenticated";
GRANT ALL ON TABLE "public"."qgen_generation_panes" TO "service_role";



GRANT ALL ON TABLE "public"."school_classes" TO "anon";
GRANT ALL ON TABLE "public"."school_classes" TO "authenticated";
GRANT ALL ON TABLE "public"."school_classes" TO "service_role";



GRANT ALL ON TABLE "public"."subjects" TO "anon";
GRANT ALL ON TABLE "public"."subjects" TO "authenticated";
GRANT ALL ON TABLE "public"."subjects" TO "service_role";



GRANT ALL ON TABLE "public"."topics" TO "anon";
GRANT ALL ON TABLE "public"."topics" TO "authenticated";
GRANT ALL ON TABLE "public"."topics" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

create extension if not exists "pg_net" with schema "public";

drop policy "Deny public access" on "public"."phonenum_otps";


  create policy "Deny public access"
  on "public"."phonenum_otps"
  as permissive
  for all
  to anon, authenticated
using (false);


CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_auth_user_created();

CREATE TRIGGER sync_last_active_trigger AFTER UPDATE OF last_sign_in_at ON auth.users FOR EACH ROW EXECUTE FUNCTION public.sync_last_active();


  create policy "Allow read"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using ((bucket_id = 'gen_images_bucket'::text));



  create policy "Allow upload"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check ((bucket_id = 'gen_images_bucket'::text));



  create policy "Users can delete their own draft logos v1"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'draft_logo_bucket'::text) AND ((storage.foldername(name))[1] IN ( SELECT (qd.activity_id)::text AS activity_id
   FROM (public.qgen_drafts qd
     JOIN public.activities a ON ((a.id = qd.activity_id)))
  WHERE (a.user_id = auth.uid())))));



  create policy "Users can insert their own draft logos v1"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'draft_logo_bucket'::text) AND ((storage.foldername(name))[1] IN ( SELECT (qd.activity_id)::text AS activity_id
   FROM (public.qgen_drafts qd
     JOIN public.activities a ON ((a.id = qd.activity_id)))
  WHERE (a.user_id = auth.uid())))));



  create policy "Users can read their own draft logos v1"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'draft_logo_bucket'::text) AND ((storage.foldername(name))[1] IN ( SELECT (qd.activity_id)::text AS activity_id
   FROM (public.qgen_drafts qd
     JOIN public.activities a ON ((a.id = qd.activity_id)))
  WHERE (a.user_id = auth.uid())))));



  create policy "Users can update their own draft logos v1"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((bucket_id = 'draft_logo_bucket'::text) AND ((storage.foldername(name))[1] IN ( SELECT (qd.activity_id)::text AS activity_id
   FROM (public.qgen_drafts qd
     JOIN public.activities a ON ((a.id = qd.activity_id)))
  WHERE (a.user_id = auth.uid())))))
with check (((bucket_id = 'draft_logo_bucket'::text) AND ((storage.foldername(name))[1] IN ( SELECT (qd.activity_id)::text AS activity_id
   FROM (public.qgen_drafts qd
     JOIN public.activities a ON ((a.id = qd.activity_id)))
  WHERE (a.user_id = auth.uid())))));



