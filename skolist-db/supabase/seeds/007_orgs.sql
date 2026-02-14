INSERT INTO "public"."orgs" ("id", "email", "logo_url", "org_type", "phone_num", "address", "header_line", "created_at", "updated_at", "board_id") VALUES 
    ('a10015f6-073c-43df-bd87-8c919a244eeb', 'jia@example.com', null, 'school', '0000000000', null, 'JIA, Rajasthan', '2026-02-04 09:40:13.732789+00', '2026-02-04 09:40:13.732789+00', '22cecc90-8749-49c8-ad21-fe64472aab14'),
    ('751434e6-0e95-4e09-8b78-1f8b1e05a94c', 'public_org@skolist.com', null, 'school', '0000000001', null, 'Public Org', '2026-02-04 09:40:13.732789+00', '2026-02-04 09:40:13.732789+00', '51b7d3cb-b469-4c4e-8c42-70d3c2388fb5')
ON CONFLICT ("id") DO NOTHING;
