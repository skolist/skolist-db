-- Add columns if not exists (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'gen_questions' AND column_name = 'is_new') THEN
        ALTER TABLE "public"."gen_questions" ADD COLUMN is_new boolean NOT NULL DEFAULT true;
    END IF;
END $$;