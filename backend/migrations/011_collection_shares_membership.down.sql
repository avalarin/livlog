-- Remove backfilled owner rows (where owner_id = shared_with_user_id, as that's how we identify backfilled rows)
DELETE FROM collection_shares
WHERE owner_id = shared_with_user_id
  AND permission_level = 'owner';
