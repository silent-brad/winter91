-- Add avatar_filename column to walker table and populate it
ALTER TABLE walker ADD COLUMN avatar_filename TEXT;

-- Update avatar_filename with format: ID_NAME.webp (replace spaces with underscores)
UPDATE walker
SET avatar_filename = id || '_' || REPLACE(name, ' ', '_') || '.webp';
