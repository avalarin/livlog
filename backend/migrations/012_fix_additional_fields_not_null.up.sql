-- Fix existing NULLs, then enforce NOT NULL with default '{}'
UPDATE entries SET additional_fields = '{}'::jsonb WHERE additional_fields IS NULL;
ALTER TABLE entries ALTER COLUMN additional_fields SET NOT NULL;
ALTER TABLE entries ALTER COLUMN additional_fields SET DEFAULT '{}'::jsonb;
