-- Add columns if not exists (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'qgen_drafts' AND column_name = 'is_show_logo') THEN
        ALTER TABLE "public"."qgen_drafts" ADD COLUMN is_show_logo boolean NOT NULL DEFAULT true;
    END IF;
END $$;