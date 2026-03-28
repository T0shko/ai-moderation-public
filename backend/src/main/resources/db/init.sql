-- Database initialization script
-- This script runs when the PostgreSQL container starts

-- Ensure the database exists (though it's created by docker-compose)
-- The database 'aimoderation' is already created via POSTGRES_DB environment variable

-- Create any additional extensions if needed
-- CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Log that initialization is complete
DO $$
BEGIN
    RAISE NOTICE 'Database aimoderation initialized successfully';
END
$$;
