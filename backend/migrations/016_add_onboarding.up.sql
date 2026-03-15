-- Add onboarding_completed to users
ALTER TABLE users ADD COLUMN onboarding_completed BOOLEAN NOT NULL DEFAULT false;
UPDATE users SET onboarding_completed = true WHERE deleted_at IS NULL;

-- Add template fields to collections
ALTER TABLE collections ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE collections ADD COLUMN is_template BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE collections ADD COLUMN slug VARCHAR(50);
ALTER TABLE collections ADD COLUMN description TEXT NOT NULL DEFAULT '';

CREATE UNIQUE INDEX idx_collections_slug ON collections(slug) WHERE slug IS NOT NULL;

-- Allow template entries without a user
ALTER TABLE entries ALTER COLUMN user_id DROP NOT NULL;

-- Seed collection templates and their entries
DO $$
DECLARE
    v_movies_id UUID;
    v_books_id UUID;
    v_vinyl_id UUID;
    v_games_id UUID;
    v_places_id UUID;
    v_movie_type_id UUID;
    v_show_type_id UUID;
    v_book_type_id UUID;
    v_music_type_id UUID;
    v_game_type_id UUID;
    v_other_type_id UUID;
BEGIN
    -- Look up system entry types
    SELECT id INTO v_movie_type_id FROM entry_types WHERE name = 'Movie' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_show_type_id FROM entry_types WHERE name = 'Show' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_book_type_id FROM entry_types WHERE name = 'Book' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_music_type_id FROM entry_types WHERE name = 'Music' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_game_type_id FROM entry_types WHERE name = 'Game' AND user_id IS NULL LIMIT 1;
    SELECT id INTO v_other_type_id FROM entry_types WHERE name = 'Other' AND user_id IS NULL LIMIT 1;

    -- Create template collections (user_id = NULL, is_template = true)
    INSERT INTO collections (user_id, name, icon, color, is_template, slug, description)
    VALUES (NULL, 'Movies & TV Shows', 'system:movie', 'coral-glow', true, 'movies', 'Track movies and TV shows you''ve watched')
    RETURNING id INTO v_movies_id;

    INSERT INTO collections (user_id, name, icon, color, is_template, slug, description)
    VALUES (NULL, 'Books', 'system:books', 'straw-gold', true, 'books', 'Keep a log of books you''ve read')
    RETURNING id INTO v_books_id;

    INSERT INTO collections (user_id, name, icon, color, is_template, slug, description)
    VALUES (NULL, 'Vinyl Records', 'system:music-record', 'vintage-grape', true, 'vinyl', 'Catalog your vinyl collection')
    RETURNING id INTO v_vinyl_id;

    INSERT INTO collections (user_id, name, icon, color, is_template, slug, description)
    VALUES (NULL, 'Games', 'system:game-controller', 'dodger-blue', true, 'games', 'Track games you''ve played')
    RETURNING id INTO v_games_id;

    INSERT INTO collections (user_id, name, icon, color, is_template, slug, description)
    VALUES (NULL, 'Places', 'system:place-marker', 'yellow-green', true, 'places', 'Remember places you''ve visited')
    RETURNING id INTO v_places_id;

    -- Movies & TV Shows entries
    INSERT INTO entries (user_id, collection_id, type_id, title, description, score, date, additional_fields) VALUES
    (NULL, v_movies_id, v_movie_type_id, 'Inception', 'A sci-fi heist thriller about a thief who steals secrets from dreams, tasked with planting an idea in a target''s mind through layered dream worlds.', 3, '2010-07-16', '{"Year": "2010", "Genre": "Sci-Fi"}'),
    (NULL, v_movies_id, v_movie_type_id, 'The Shawshank Redemption', 'Two imprisoned men bond over a number of years, finding solace and eventual redemption through acts of common decency.', 3, '1994-10-14', '{"Year": "1994", "Genre": "Drama"}'),
    (NULL, v_movies_id, v_show_type_id, 'Breaking Bad', 'A high school chemistry teacher turned methamphetamine manufacturer partners with a former student to secure his family''s financial future.', 3, '2008-01-20', '{"Year": "2008", "Genre": "Drama"}'),
    (NULL, v_movies_id, v_movie_type_id, 'Interstellar', 'A team of explorers travel through a wormhole in space in an attempt to ensure humanity''s survival.', 3, '2014-11-07', '{"Year": "2014", "Genre": "Sci-Fi"}'),
    (NULL, v_movies_id, v_movie_type_id, 'Parasite', 'Greed and class discrimination threaten the newly formed symbiotic relationship between the wealthy Park family and the destitute Kim clan.', 3, '2019-05-30', '{"Year": "2019", "Genre": "Thriller"}');

    -- Books entries
    INSERT INTO entries (user_id, collection_id, type_id, title, description, score, date, additional_fields) VALUES
    (NULL, v_books_id, v_book_type_id, '1984', 'Orwell''s bleak dystopia of a totalitarian state that controls through surveillance, propaganda, and the erosion of individual freedom.', 3, '1949-06-08', '{"Year": "1949", "Author": "George Orwell"}'),
    (NULL, v_books_id, v_book_type_id, 'To Kill a Mockingbird', 'The story of racial injustice and the loss of innocence in the American South, seen through the eyes of young Scout Finch.', 3, '1960-07-11', '{"Year": "1960", "Author": "Harper Lee"}'),
    (NULL, v_books_id, v_book_type_id, 'The Great Gatsby', 'A tale of wealth, love, and the American Dream set in the Jazz Age, narrated by Nick Carraway about the mysterious Jay Gatsby.', 2, '1925-04-10', '{"Year": "1925", "Author": "F. Scott Fitzgerald"}'),
    (NULL, v_books_id, v_book_type_id, 'Sapiens', 'A brief history of humankind that explores how Homo sapiens came to dominate the world through cognitive, agricultural, and scientific revolutions.', 3, '2011-01-01', '{"Year": "2011", "Author": "Yuval Noah Harari"}'),
    (NULL, v_books_id, v_book_type_id, 'Dune', 'An epic science fiction saga of politics, religion, and ecology on the desert planet Arrakis, following young Paul Atreides.', 3, '1965-08-01', '{"Year": "1965", "Author": "Frank Herbert"}');

    -- Vinyl Records entries
    INSERT INTO entries (user_id, collection_id, type_id, title, description, score, date, additional_fields) VALUES
    (NULL, v_vinyl_id, v_music_type_id, 'The Dark Side of the Moon', 'Pink Floyd''s legendary concept album exploring themes of conflict, greed, time, and mental illness.', 3, '1973-03-01', '{"Year": "1973", "Artist": "Pink Floyd"}'),
    (NULL, v_vinyl_id, v_music_type_id, 'Abbey Road', 'The Beatles'' iconic final recorded album, featuring a seamless medley and some of their most beloved songs.', 3, '1969-09-26', '{"Year": "1969", "Artist": "The Beatles"}'),
    (NULL, v_vinyl_id, v_music_type_id, 'Rumours', 'Fleetwood Mac''s masterpiece born from personal turmoil, blending pop, rock, and folk into timeless tracks.', 3, '1977-02-04', '{"Year": "1977", "Artist": "Fleetwood Mac"}'),
    (NULL, v_vinyl_id, v_music_type_id, 'Kind of Blue', 'Miles Davis'' modal jazz landmark that redefined the genre and remains one of the best-selling jazz albums of all time.', 3, '1959-08-17', '{"Year": "1959", "Artist": "Miles Davis"}'),
    (NULL, v_vinyl_id, v_music_type_id, 'OK Computer', 'Radiohead''s ambitious third album that blends rock with electronic textures, exploring themes of modern alienation.', 3, '1997-06-16', '{"Year": "1997", "Artist": "Radiohead"}');

    -- Games entries
    INSERT INTO entries (user_id, collection_id, type_id, title, description, score, date, additional_fields) VALUES
    (NULL, v_games_id, v_game_type_id, 'The Witcher 3: Wild Hunt', 'An epic open-world RPG following Geralt of Rivia as he searches for his adopted daughter while navigating a war-torn fantasy continent.', 3, '2015-05-19', '{"Year": "2015", "Platform": "PC"}'),
    (NULL, v_games_id, v_game_type_id, 'Elden Ring', 'A demanding open-world adventure that tests your patience and skill, rewarding you with memorable discoveries and the satisfaction of overcoming obstacles.', 3, '2022-02-25', '{"Year": "2022", "Platform": "PC"}'),
    (NULL, v_games_id, v_game_type_id, 'Red Dead Redemption 2', 'An epic tale of life in America''s unforgiving heartland, following outlaw Arthur Morgan and the Van der Linde gang.', 3, '2018-10-26', '{"Year": "2018", "Platform": "PS4"}'),
    (NULL, v_games_id, v_game_type_id, 'Zelda: Breath of the Wild', 'An open-air adventure that breaks conventions of the Zelda series, offering unprecedented freedom to explore the kingdom of Hyrule.', 3, '2017-03-03', '{"Year": "2017", "Platform": "Switch"}'),
    (NULL, v_games_id, v_game_type_id, 'Hades', 'A rogue-like dungeon crawler where you defy the god of the dead as you hack and slash your way out of the Underworld.', 3, '2020-09-17', '{"Year": "2020", "Platform": "PC"}');

    -- Places entries
    INSERT INTO entries (user_id, collection_id, type_id, title, description, score, date, additional_fields) VALUES
    (NULL, v_places_id, v_other_type_id, 'Central Park, NYC', 'An urban oasis in the heart of Manhattan, perfect for walks, picnics, and people-watching across 843 acres of green space.', 3, '2024-06-15', '{}'),
    (NULL, v_places_id, v_other_type_id, 'Eiffel Tower, Paris', 'The iconic iron lattice tower offering breathtaking views of Paris from its observation decks, especially magical at night.', 3, '2024-03-20', '{}'),
    (NULL, v_places_id, v_other_type_id, 'Fushimi Inari, Kyoto', 'Thousands of vermillion torii gates wind through the forested hillside of this ancient Shinto shrine, creating an unforgettable path.', 3, '2024-09-10', '{}'),
    (NULL, v_places_id, v_other_type_id, 'Machu Picchu, Peru', 'The 15th-century Incan citadel set high in the Andes Mountains, a testament to ancient engineering and a wonder of the world.', 3, '2024-01-05', '{}'),
    (NULL, v_places_id, v_other_type_id, 'Santorini, Greece', 'A stunning volcanic island with white-washed buildings, blue-domed churches, and spectacular sunsets over the Aegean Sea.', 2, '2024-07-22', '{}');

    -- Copy seed images to template entries that have matching covers
    INSERT INTO entry_images (entry_id, image_data, is_cover, position, hash)
    SELECT e.id, si.image_data, true, 0, encode(sha256(si.image_data), 'hex')
    FROM entries e, seed_images si
    WHERE e.collection_id = v_movies_id AND e.title = 'Inception'
      AND si.id = '00000000-0000-0000-0001-000000000001';

    INSERT INTO entry_images (entry_id, image_data, is_cover, position, hash)
    SELECT e.id, si.image_data, true, 0, encode(sha256(si.image_data), 'hex')
    FROM entries e, seed_images si
    WHERE e.collection_id = v_books_id AND e.title = '1984'
      AND si.id = '00000000-0000-0000-0001-000000000002';

    INSERT INTO entry_images (entry_id, image_data, is_cover, position, hash)
    SELECT e.id, si.image_data, true, 0, encode(sha256(si.image_data), 'hex')
    FROM entries e, seed_images si
    WHERE e.collection_id = v_games_id AND e.title = 'Elden Ring'
      AND si.id = '00000000-0000-0000-0001-000000000003';

    INSERT INTO entry_images (entry_id, image_data, is_cover, position, hash)
    SELECT e.id, si.image_data, true, 0, encode(sha256(si.image_data), 'hex')
    FROM entries e, seed_images si
    WHERE e.collection_id = v_vinyl_id AND e.title = 'OK Computer'
      AND si.id = '00000000-0000-0000-0001-000000000005';
END $$;
