-- Add color column to collections
ALTER TABLE collections ADD COLUMN color VARCHAR(30) NOT NULL DEFAULT 'dodger-blue';

-- Expand icon column to fit system:icon-name format
ALTER TABLE collections ALTER COLUMN icon TYPE VARCHAR(50);

-- Migrate existing data to new format
UPDATE collections SET icon = 'system:folder', color = 'dodger-blue';
