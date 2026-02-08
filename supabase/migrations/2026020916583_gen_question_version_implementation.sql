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