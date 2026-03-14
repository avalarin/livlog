CREATE TABLE tags (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) NOT NULL,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Enforce uniqueness: two tags with the same name may not share the same user_id (or both be system tags).
-- COALESCE replaces NULL (system tag) with a sentinel UUID so the expression is never NULL.
CREATE UNIQUE INDEX uq_tags_name_user ON tags (name, COALESCE(user_id, '00000000-0000-0000-0000-000000000000'));

CREATE TABLE entry_tags (
    entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    tag_id UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (entry_id, tag_id)
);

-- Seed system "mcp" tag (user_id = NULL means system tag)
INSERT INTO tags (name) VALUES ('mcp');
