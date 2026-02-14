-- Add columns if not exists (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'qgen_drafts' AND column_name = 'is_show_instruction') THEN
        ALTER TABLE "public"."qgen_drafts" ADD COLUMN is_show_instruction boolean NOT NULL DEFAULT true;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'qgen_drafts' AND column_name = 'is_show_explanation_answer_key') THEN ALTER TABLE "public"."qgen_drafts" ADD COLUMN is_show_explanation_answer_key boolean NOT NULL DEFAULT true; END IF;
END $$;