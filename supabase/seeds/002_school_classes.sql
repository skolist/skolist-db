-- Data for Name: school_classes; Type: TABLE DATA; Schema: public; Owner: postgres

INSERT INTO "public"."school_classes" ("id", "name", "description", "board_id", "position", "created_at", "updated_at") VALUES
	('e763c901-a3b9-4472-9016-cebfa7a39902', 'Class 10', NULL, '51b7d3cb-b469-4c4e-8c42-70d3c2388fb5', 10, '2025-12-30 19:10:59.829087+00', '2025-12-30 19:10:59.829087+00'),
	('79eea6a5-591a-4d2b-829f-357f4f2ec236', 'Class 12', 'The Class 12th of the CBSE Board.', '51b7d3cb-b469-4c4e-8c42-70d3c2388fb5', 12, '2026-01-03 15:24:33.073555+00', '2026-01-03 15:24:33.073555+00')
ON CONFLICT ("id") DO NOTHING;

INSERT INTO "public"."school_classes" ("id", "name", "description", "board_id", "position", "created_at", "updated_at") 
VALUES ('cc20f630-f811-49a2-ba21-632562b16ad0', 'Class 6', '6th Class of RBSE Board', '22cecc90-8749-49c8-ad21-fe64472aab14', '6', '2026-02-04 09:29:24.233671+00', '2026-02-04 09:29:24.233671+00')
ON CONFLICT ("id") DO NOTHING;
