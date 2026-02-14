-- Add columns if not exists (idempotent)
DO $$
BEGIN

    -- Stores actual question data
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_question_versions' AND column_name = 'is_active') THEN
        ALTER TABLE "public"."gen_question_versions" ADD COLUMN is_active boolean NOT NULL DEFAULT true;
    END IF;
    -- Soft delete, not actually deleting the data, but undo redo can't reach here ever
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_question_versions' AND column_name = 'is_deleted') THEN
        ALTER TABLE "public"."gen_question_versions" ADD COLUMN is_deleted boolean NOT NULL DEFAULT false;
    END IF;
    -- Version index (starting from 0 for a question in ascending order of each question's version creation)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_question_versions' AND column_name = 'version_index') THEN
        ALTER TABLE "public"."gen_question_versions" ADD COLUMN version_index integer NOT NULL DEFAULT 0;
    END IF;

    -- Only one version can be active at a time for a given gen_question_id
    CREATE UNIQUE INDEX IF NOT EXISTS gen_question_versions_active_idx
    ON "public"."gen_question_versions" (gen_question_id)
    WHERE is_active = true AND is_deleted = false;

    -- A deleted question can never be active
    ALTER TABLE "public"."gen_question_versions" ADD CONSTRAINT gen_question_versions_active_check CHECK (is_deleted = false OR is_active = false);

    -- Policy such that the activity owner can access the versions of the question's he accesses
    CREATE POLICY "activity_owner_all" ON "public"."gen_question_versions" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM ("public"."gen_questions" "gq"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "gq"."activity_id")))
  WHERE (("gq"."id" = "gen_question_versions"."gen_question_id") AND ("ac"."user_id" = "auth"."uid"()))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM ("public"."gen_questions" "gq"
     JOIN "public"."activities" "ac" ON (("ac"."id" = "gq"."activity_id")))
  WHERE (("gq"."id" = "gen_question_versions"."gen_question_id") AND ("ac"."user_id" = "auth"."uid"())))));
END $$;