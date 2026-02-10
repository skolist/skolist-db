-- Add columns (test user tag) if not exists (idempotent)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'is_test_user') THEN
        ALTER TABLE "public"."users" ADD COLUMN is_test_user boolean NOT NULL DEFAULT false;
    END IF;
END $$;