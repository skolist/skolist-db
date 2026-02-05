INSERT INTO "public"."boards" ("id", "name", "description", "created_at", "updated_at") VALUES
	('51b7d3cb-b469-4c4e-8c42-70d3c2388fb5', 'CBSE', 'Central Board of Secondary Education', '2025-12-29 06:50:02.4835+00', '2025-12-29 06:50:02.4835+00'),
	('5bfd6fdb-1969-4652-8a45-5ff02f272871', 'ICSE', 'Indian Certificate of Secondary Education', '2025-12-29 06:50:32.106398+00', '2025-12-29 06:50:32.106398+00'),
	('57d09061-8004-45a2-8e2b-90c34630ef82', 'MHSBSHE', 'Maharashtra State Board of Secondary And Higher Education', '2025-12-29 06:55:24.699458+00', '2025-12-29 06:55:24.699458+00')
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "public"."boards" ("id", "name", "description", "created_at", "updated_at") VALUES ('22cecc90-8749-49c8-ad21-fe64472aab14', 'RBSE', null, '2026-02-04 09:28:47.777349+00', '2026-02-04 09:28:47.777349+00')
ON CONFLICT ("id") DO NOTHING;