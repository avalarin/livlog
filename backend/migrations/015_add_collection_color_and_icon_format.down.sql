-- Revert icon values back to emoji
UPDATE collections SET icon = '📁';

-- Shrink icon column back
ALTER TABLE collections ALTER COLUMN icon TYPE VARCHAR(20);

-- Drop color column
ALTER TABLE collections DROP COLUMN color;
