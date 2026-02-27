ALTER TABLE entry_types ADD COLUMN fields JSONB NOT NULL DEFAULT '[]'::jsonb;

UPDATE entry_types SET fields = '[
  {"key": "Year", "label": "Year", "type": "number"},
  {"key": "Genre", "label": "Genre", "type": "string"}
]'::jsonb WHERE name = 'Movie' AND user_id IS NULL;

UPDATE entry_types SET fields = '[
  {"key": "Year", "label": "Year", "type": "number"},
  {"key": "Author", "label": "Author", "type": "string"}
]'::jsonb WHERE name = 'Book' AND user_id IS NULL;

UPDATE entry_types SET fields = '[
  {"key": "Year", "label": "Year", "type": "number"},
  {"key": "Platform", "label": "Platform", "type": "string"}
]'::jsonb WHERE name = 'Game' AND user_id IS NULL;

UPDATE entry_types SET fields = '[
  {"key": "Year", "label": "Year", "type": "number"},
  {"key": "Genre", "label": "Genre", "type": "string"}
]'::jsonb WHERE name = 'Show' AND user_id IS NULL;

UPDATE entry_types SET fields = '[
  {"key": "Year", "label": "Year", "type": "number"},
  {"key": "Artist", "label": "Artist", "type": "string"}
]'::jsonb WHERE name = 'Music' AND user_id IS NULL;
