ALTER TABLE entry_images ADD COLUMN hash VARCHAR(64);
UPDATE entry_images SET hash = encode(sha256(image_data), 'hex');
ALTER TABLE entry_images ALTER COLUMN hash SET NOT NULL;
