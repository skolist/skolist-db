-- Add columns if not exists (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_question_versions' AND column_name = 'is_active') THEN
        ALTER TABLE "public"."gen_question_versions" ADD COLUMN is_active boolean NOT NULL DEFAULT true;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_question_versions' AND column_name = 'is_deleted') THEN
        ALTER TABLE "public"."gen_question_versions" ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_question_versions' AND column_name = 'version_index') THEN
        ALTER TABLE "public"."gen_question_versions" ADD COLUMN version_index integer NOT NULL DEFAULT 0;
    END IF;
END $$;


-- RPC: Get Question Details (Data + Concepts + Images + Version Info)
CREATE OR REPLACE FUNCTION get_question_details(p_question_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_question JSONB;
  v_concepts JSONB;
  v_images JSONB;
  v_current_version_index INTEGER;
  v_max_version_index INTEGER;
  v_can_undo BOOLEAN;
  v_can_redo BOOLEAN;
BEGIN
  -- Fetch question data
  SELECT to_jsonb(q) INTO v_question FROM gen_questions q WHERE id = p_question_id;
  
  -- Fetch concepts
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name)), '[]'::jsonb)
  INTO v_concepts
  FROM gen_questions_concepts_maps m
  JOIN concepts c ON c.id = m.concept_id
  WHERE m.gen_question_id = p_question_id;
  
  -- Fetch images
  SELECT COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.position), '[]'::jsonb)
  INTO v_images
  FROM gen_images i
  WHERE gen_question_id = p_question_id AND (svg_string IS NOT NULL OR img_url IS NOT NULL);
  
  -- Fetch version info
  SELECT version_index INTO v_current_version_index
  FROM gen_question_versions
  WHERE gen_question_id = p_question_id AND is_active = true
  LIMIT 1;
  
  IF v_current_version_index IS NULL THEN
     v_current_version_index := 0; 
  END IF;

  -- Check Undo/Redo availability
  -- Can Undo if there is a version with index < current which is not deleted
  SELECT EXISTS(
    SELECT 1 FROM gen_question_versions 
    WHERE gen_question_id = p_question_id 
    AND version_index < v_current_version_index 
    AND is_deleted = false
  ) INTO v_can_undo;

  -- Can Redo if there is a version with index > current which is not deleted
  SELECT EXISTS(
    SELECT 1 FROM gen_question_versions 
    WHERE gen_question_id = p_question_id 
    AND version_index > v_current_version_index 
    AND is_deleted = false
  ) INTO v_can_redo;

  RETURN jsonb_build_object(
    'question', v_question,
    'concepts', v_concepts,
    'images', v_images,
    'current_version_index', v_current_version_index,
    'can_undo', v_can_undo,
    'can_redo', v_can_redo
  );
END;
$$ LANGUAGE plpgsql;


-- RPC: Create Question Version (Sync Strategy - Update Then Snapshot)
CREATE OR REPLACE FUNCTION create_question_version(
  p_question_id UUID,
  p_new_data JSONB
) RETURNS VOID AS $$
DECLARE
  v_current_index INTEGER;
  v_new_index INTEGER;
  v_original_row gen_questions%ROWTYPE;
  v_full_row gen_questions%ROWTYPE;
  v_has_versions BOOLEAN;
BEGIN
  -- 1. Check if this question has any versions yet
  SELECT EXISTS(
    SELECT 1 FROM gen_question_versions WHERE gen_question_id = p_question_id
  ) INTO v_has_versions;

  -- 2. If NO versions exist, snapshot the ORIGINAL state as version 0 first
  IF NOT v_has_versions THEN
    -- Fetch current state BEFORE update
    SELECT * INTO v_original_row FROM gen_questions WHERE id = p_question_id;
    
    -- Insert version 0 (original state, NOT active since we're about to create version 1)
    INSERT INTO gen_question_versions (
      gen_question_id, version_index, is_active, is_deleted, 
      question_text, answer_text, marks, hardness_level, explanation, 
      question_type, option1, option2, option3, option4, match_the_following_columns
    )
    VALUES (
      p_question_id, 
      0, 
      false,  -- Not active, version 1 will be active
      false,
      v_original_row.question_text,
      v_original_row.answer_text,
      v_original_row.marks,
      v_original_row.hardness_level,
      v_original_row.explanation,
      v_original_row.question_type,
      v_original_row.option1,
      v_original_row.option2,
      v_original_row.option3,
      v_original_row.option4,
      v_original_row.match_the_following_columns
    );
  END IF;

  -- 3. Update gen_questions with new data (handles partial updates via COALESCE)
  UPDATE gen_questions
  SET
    question_text = COALESCE((p_new_data->>'question_text')::text, question_text),
    answer_text = COALESCE((p_new_data->>'answer_text')::text, answer_text),
    marks = COALESCE((p_new_data->>'marks')::numeric, marks),
    hardness_level = COALESCE((p_new_data->>'hardness_level')::public.hardness_level_enum, hardness_level),
    explanation = COALESCE((p_new_data->>'explanation')::text, explanation),
    question_type = COALESCE((p_new_data->>'question_type')::public.question_type_enum, question_type),
    option1 = COALESCE((p_new_data->>'option1')::text, option1),
    option2 = COALESCE((p_new_data->>'option2')::text, option2),
    option3 = COALESCE((p_new_data->>'option3')::text, option3),
    option4 = COALESCE((p_new_data->>'option4')::text, option4),
    match_the_following_columns = COALESCE((p_new_data->>'match_the_following_columns')::jsonb, match_the_following_columns),
    updated_at = now()
  WHERE id = p_question_id
  RETURNING * INTO v_full_row;

  -- 4. Determine new version index
  SELECT COALESCE(MAX(version_index), 0) INTO v_current_index
  FROM gen_question_versions
  WHERE gen_question_id = p_question_id AND is_active = true;

  -- If no active version found, use max index overall
  IF v_current_index = 0 THEN
      SELECT COALESCE(MAX(version_index), 0) INTO v_current_index
      FROM gen_question_versions
      WHERE gen_question_id = p_question_id;
  END IF;

  v_new_index := v_current_index + 1;

  -- 5. Mark "future" versions as deleted (branching)
  UPDATE gen_question_versions
  SET is_deleted = true
  WHERE gen_question_id = p_question_id AND version_index > v_current_index;

  -- 6. Deactivate all versions
  UPDATE gen_question_versions
  SET is_active = false
  WHERE gen_question_id = p_question_id;

  -- 7. Insert NEW version as ACTIVE
  INSERT INTO gen_question_versions (
    gen_question_id, version_index, is_active, is_deleted, 
    question_text, answer_text, marks, hardness_level, explanation, 
    question_type, option1, option2, option3, option4, match_the_following_columns
  )
  VALUES (
    p_question_id, 
    v_new_index, 
    true, 
    false,
    v_full_row.question_text,
    v_full_row.answer_text,
    v_full_row.marks,
    v_full_row.hardness_level,
    v_full_row.explanation,
    v_full_row.question_type,
    v_full_row.option1,
    v_full_row.option2,
    v_full_row.option3,
    v_full_row.option4,
    v_full_row.match_the_following_columns
  );

END;
$$ LANGUAGE plpgsql;


-- RPC: Undo Question
CREATE OR REPLACE FUNCTION undo_question(p_question_id UUID)
RETURNS VOID AS $$
DECLARE
  v_current_index INTEGER;
  v_prev_index INTEGER;
  v_prev_version RECORD;
BEGIN
  -- Get current active version
  SELECT version_index INTO v_current_index
  FROM gen_question_versions
  WHERE gen_question_id = p_question_id AND is_active = true
  LIMIT 1;

  IF v_current_index IS NULL THEN
      RETURN; -- Or raise error
  END IF;

  -- Find previous version (latest one before current that is not deleted)
  SELECT version_index INTO v_prev_index
  FROM gen_question_versions
  WHERE gen_question_id = p_question_id 
    AND version_index < v_current_index 
    AND is_deleted = false
  ORDER BY version_index DESC
  LIMIT 1;

  IF v_prev_index IS NULL THEN
      RETURN; -- Cannot undo
  END IF;

  -- Deactivate current
  UPDATE gen_question_versions
  SET is_active = false
  WHERE gen_question_id = p_question_id AND version_index = v_current_index;

  -- Activate previous
  UPDATE gen_question_versions
  SET is_active = true
  WHERE gen_question_id = p_question_id AND version_index = v_prev_index
  RETURNING * INTO v_prev_version;

  -- Sync gen_questions
  UPDATE gen_questions
  SET
    question_text = v_prev_version.question_text,
    answer_text = v_prev_version.answer_text,
    marks = v_prev_version.marks,
    hardness_level = v_prev_version.hardness_level,
    explanation = v_prev_version.explanation,
    question_type = v_prev_version.question_type,
    option1 = v_prev_version.option1,
    option2 = v_prev_version.option2,
    option3 = v_prev_version.option3,
    option4 = v_prev_version.option4,
    match_the_following_columns = v_prev_version.match_the_following_columns,
    updated_at = now()
  WHERE id = p_question_id;

END;
$$ LANGUAGE plpgsql;


-- RPC: Redo Question
CREATE OR REPLACE FUNCTION redo_question(p_question_id UUID)
RETURNS VOID AS $$
DECLARE
  v_current_index INTEGER;
  v_next_index INTEGER;
  v_next_version RECORD;
BEGIN
  -- Get current active version
  SELECT version_index INTO v_current_index
  FROM gen_question_versions
  WHERE gen_question_id = p_question_id AND is_active = true
  LIMIT 1;

  IF v_current_index IS NULL THEN
      RETURN;
  END IF;

  -- Find next version (first one after current that is not deleted)
  SELECT version_index INTO v_next_index
  FROM gen_question_versions
  WHERE gen_question_id = p_question_id 
    AND version_index > v_current_index 
    AND is_deleted = false
  ORDER BY version_index ASC
  LIMIT 1;

  IF v_next_index IS NULL THEN
      RETURN; -- Cannot redo
  END IF;

  -- Deactivate current
  UPDATE gen_question_versions
  SET is_active = false
  WHERE gen_question_id = p_question_id AND version_index = v_current_index;

  -- Activate next
  UPDATE gen_question_versions
  SET is_active = true
  WHERE gen_question_id = p_question_id AND version_index = v_next_index
  RETURNING * INTO v_next_version;

  -- Sync gen_questions
  UPDATE gen_questions
  SET
    question_text = v_next_version.question_text,
    answer_text = v_next_version.answer_text,
    marks = v_next_version.marks,
    hardness_level = v_next_version.hardness_level,
    explanation = v_next_version.explanation,
    question_type = v_next_version.question_type,
    option1 = v_next_version.option1,
    option2 = v_next_version.option2,
    option3 = v_next_version.option3,
    option4 = v_next_version.option4,
    match_the_following_columns = v_next_version.match_the_following_columns,
    updated_at = now()
  WHERE id = p_question_id;

END;
$$ LANGUAGE plpgsql;


-- RPC: Get All Questions for Activity (Bulk fetch with version flags)
CREATE OR REPLACE FUNCTION get_questions_for_activity(p_activity_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'question', to_jsonb(q),
      'concepts', COALESCE((
        SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name))
        FROM gen_questions_concepts_maps m
        JOIN concepts c ON c.id = m.concept_id
        WHERE m.gen_question_id = q.id
      ), '[]'::jsonb),
      'images', COALESCE((
        SELECT jsonb_agg(to_jsonb(i) ORDER BY i.position)
        FROM gen_images i
        WHERE i.gen_question_id = q.id AND (i.svg_string IS NOT NULL OR i.img_url IS NOT NULL)
      ), '[]'::jsonb),
      'can_undo', EXISTS(
        SELECT 1 FROM gen_question_versions v
        WHERE v.gen_question_id = q.id 
        AND v.is_deleted = false 
        AND v.version_index < COALESCE((
          SELECT version_index FROM gen_question_versions 
          WHERE gen_question_id = q.id AND is_active = true LIMIT 1
        ), 0)
      ),
      'can_redo', EXISTS(
        SELECT 1 FROM gen_question_versions v
        WHERE v.gen_question_id = q.id 
        AND v.is_deleted = false 
        AND v.version_index > COALESCE((
          SELECT version_index FROM gen_question_versions 
          WHERE gen_question_id = q.id AND is_active = true LIMIT 1
        ), 0)
      )
    ) ORDER BY q.created_at ASC
  ), '[]'::jsonb)
  INTO v_result
  FROM gen_questions q
  WHERE q.activity_id = p_activity_id;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql;


-- RLS Policy for gen_question_versions (similar to gen_questions)
-- Users can only access versions of questions they own (via activity ownership)
CREATE POLICY "activity_owner_all" ON "public"."gen_question_versions" 
TO "authenticated" 
USING (
  EXISTS (
    SELECT 1
    FROM "public"."gen_questions" "gq"
    JOIN "public"."activities" "a" ON "a"."id" = "gq"."activity_id"
    WHERE "gq"."id" = "gen_question_versions"."gen_question_id" 
    AND "a"."user_id" = "auth"."uid"()
  )
) 
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM "public"."gen_questions" "gq"
    JOIN "public"."activities" "a" ON "a"."id" = "gq"."activity_id"
    WHERE "gq"."id" = "gen_question_versions"."gen_question_id" 
    AND "a"."user_id" = "auth"."uid"()
  )
);
