-- Backfill existing collection owners into collection_shares
INSERT INTO collection_shares (collection_id, owner_id, shared_with_user_id, permission_level)
SELECT id, user_id, user_id, 'owner'
FROM collections
ON CONFLICT (collection_id, shared_with_user_id) DO NOTHING;
