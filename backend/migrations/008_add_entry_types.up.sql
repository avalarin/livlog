-- Create entry_types table
CREATE TABLE entry_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(50) NOT NULL,
    icon VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_entry_types_user_id ON entry_types(user_id);

-- Insert default system types (user_id = NULL means system type)
INSERT INTO entry_types (name, icon) VALUES
    ('Movie', '🎬'),
    ('Book', '📚'),
    ('Game', '🎮'),
    ('Show', '📺'),
    ('Music', '🎵'),
    ('Other', '📝');

-- Add type_id to entries
ALTER TABLE entries ADD COLUMN type_id UUID REFERENCES entry_types(id) ON DELETE SET NULL;
CREATE INDEX idx_entries_type_id ON entries(type_id);

-- Change collection FK on entries from SET NULL to CASCADE
ALTER TABLE entries DROP CONSTRAINT entries_collection_id_fkey;
ALTER TABLE entries ADD CONSTRAINT entries_collection_id_fkey
    FOREIGN KEY (collection_id) REFERENCES collections(id) ON DELETE CASCADE;

-- Data migration: for each user create "My List", then move all entries into it
DO $$
DECLARE
    v_user_id UUID;
    v_my_list_id UUID;
    v_movie_type_id UUID;
    v_book_type_id UUID;
    v_game_type_id UUID;
    v_show_type_id UUID;
    v_music_type_id UUID;
    v_other_type_id UUID;
BEGIN
    SELECT id INTO v_movie_type_id FROM entry_types WHERE name = 'Movie' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_book_type_id FROM entry_types WHERE name = 'Book' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_game_type_id FROM entry_types WHERE name = 'Game' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_show_type_id FROM entry_types WHERE name = 'Show' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_music_type_id FROM entry_types WHERE name = 'Music' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_other_type_id FROM entry_types WHERE name = 'Other' AND user_id IS NULL LIMIT 1;

    FOR v_user_id IN SELECT id FROM users WHERE deleted_at IS NULL LOOP
        -- Create My List collection for user
        INSERT INTO collections (user_id, name, icon)
        VALUES (v_user_id, 'My List', '📋')
        RETURNING id INTO v_my_list_id;

        -- Move entries that belong to this user's existing collections, setting type by old collection name
        UPDATE entries e
        SET
            collection_id = v_my_list_id,
            type_id = CASE
                WHEN LOWER(c.name) IN ('movies', 'movie') THEN v_movie_type_id
                WHEN LOWER(c.name) IN ('books', 'book') THEN v_book_type_id
                WHEN LOWER(c.name) IN ('games', 'game') THEN v_game_type_id
                WHEN LOWER(c.name) IN ('shows', 'show', 'tv shows', 'tv') THEN v_show_type_id
                WHEN LOWER(c.name) IN ('music', 'concert', 'concerts') THEN v_music_type_id
                ELSE v_other_type_id
            END
        FROM collections c
        WHERE e.collection_id = c.id
          AND c.user_id = v_user_id;

        -- Move uncollected entries to My List
        UPDATE entries
        SET collection_id = v_my_list_id
        WHERE user_id = v_user_id
          AND collection_id IS NULL;

        -- Delete old collections for this user (except My List just created)
        DELETE FROM collections
        WHERE user_id = v_user_id
          AND id != v_my_list_id;
    END LOOP;
END $$;
