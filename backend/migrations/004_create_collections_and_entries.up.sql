-- Create collections table
CREATE TABLE collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(50) NOT NULL,
    icon VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_collections_user_id ON collections(user_id);

-- Create collection_shares table (for future sharing functionality)
CREATE TABLE collection_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
    owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    shared_with_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    permission_level VARCHAR(20) NOT NULL DEFAULT 'read',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_collection_share UNIQUE (collection_id, shared_with_user_id)
);

CREATE INDEX idx_collection_shares_collection_id ON collection_shares(collection_id);
CREATE INDEX idx_collection_shares_shared_with ON collection_shares(shared_with_user_id);

-- Create entries table
CREATE TABLE entries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collection_id UUID REFERENCES collections(id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL CHECK (char_length(description) <= 2000),
    score SMALLINT NOT NULL CHECK (score >= 0 AND score <= 3),
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    additional_fields JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_entries_user_id ON entries(user_id);
CREATE INDEX idx_entries_collection_id ON entries(collection_id);
CREATE INDEX idx_entries_date ON entries(date DESC);
CREATE INDEX idx_entries_created_at ON entries(created_at DESC);

-- GIN index for JSONB additional_fields for fast queries
CREATE INDEX idx_entries_additional_fields ON entries USING GIN (additional_fields);

-- Create entry_images table
CREATE TABLE entry_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    entry_id UUID NOT NULL REFERENCES entries(id) ON DELETE CASCADE,
    image_data BYTEA NOT NULL,
    is_cover BOOLEAN NOT NULL DEFAULT false,
    position INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_entry_images_entry_id ON entry_images(entry_id);
CREATE INDEX idx_entry_images_position ON entry_images(entry_id, position);
