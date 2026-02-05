SET session_replication_role = replica;

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


-- Including the modular files
\i supabase/seeds/001_boards.sql
\i supabase/seeds/002_school_classes.sql
\i supabase/seeds/003_subjects.sql
\i supabase/seeds/004_chapters.sql
\i supabase/seeds/005_topics.sql
\i supabase/seeds/006_concepts.sql
\i supabase/seeds/007_orgs.sql
\i supabase/seeds/008_bank_questions.sql
\i supabase/seeds/009_bank_questions_concepts_maps.sql
-- RE-ENABLE triggers when finished (Crucial!)
SET session_replication_role = DEFAULT;