CREATE OR REPLACE FUNCTION public.apply_public_rls_policies(schema_name TEXT, table_name TEXT) 
RETURNS void AS $$
DECLARE
    policy_name TEXT;
    full_table_name TEXT;
BEGIN
    full_table_name := schema_name || '.' || table_name;

    -- Enable RLS on the table
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name, table_name);

    -- Drop existing policies
    FOR policy_name IN (
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = schema_name AND tablename = table_name
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', policy_name, schema_name, table_name);
    END LOOP; 

    -- Update the public visibility policy to check for keep_private more efficiently
    EXECUTE format('
        CREATE POLICY "Tweets are publicly visible unless marked private" ON %I.%I
        FOR SELECT
        USING (
            (SELECT COALESCE(au.keep_private, false) 
             FROM archive_upload au 
             WHERE au.id = %I.archive_upload_id) = false
            OR account_id = (SELECT auth.jwt() -> ''app_metadata'' ->> ''provider_id'')::UUID
        )', schema_name, table_name, table_name);

    -- The modification policy remains unchanged
    EXECUTE format('
        CREATE POLICY "Tweets are modifiable by their users" ON %I.%I TO authenticated 
        USING (
            account_id = (SELECT auth.jwt()) -> ''app_metadata'' ->> ''provider_id''
        ) 
        WITH CHECK (
            account_id = (SELECT auth.jwt()) -> ''app_metadata'' ->> ''provider_id''
        )', schema_name, table_name);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.apply_public_entities_rls_policies(schema_name TEXT, table_name TEXT) 
RETURNS void AS $$
DECLARE
    policy_name TEXT;
    full_table_name TEXT;
BEGIN
    full_table_name := schema_name || '.' || table_name;

    -- Enable RLS on the table
    EXECUTE format('ALTER TABLE %I.%I ENABLE ROW LEVEL SECURITY', schema_name, table_name);

    -- Drop existing policies
    FOR policy_name IN (
        SELECT policyname
        FROM pg_policies
        WHERE schemaname = schema_name AND tablename = table_name
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', policy_name, schema_name, table_name);
    END LOOP;

    EXECUTE format('
        CREATE POLICY "Tweets are publicly visible unless marked private" ON %I.%I
        FOR SELECT
        USING (
            (SELECT COALESCE(au.keep_private, false) 
             FROM archive_upload au 
             WHERE au.id = %I.archive_upload_id) = false
            OR account_id = (SELECT auth.jwt() -> ''app_metadata'' ->> ''provider_id'')::UUID
        )', schema_name, table_name, table_name);

    EXECUTE format('
        CREATE POLICY "Entities are modifiable by their users" ON %I.%I TO authenticated
        USING (
            EXISTS (
                SELECT 1 
                FROM public.tweets dt 
                WHERE dt.tweet_id = %I.tweet_id 
                AND dt.account_id = (SELECT auth.jwt()) -> ''app_metadata'' ->> ''provider_id''
            )
        ) 
        WITH CHECK (
            EXISTS (
                SELECT 1 
                FROM public.tweets dt 
                WHERE dt.tweet_id = %I.tweet_id 
                AND dt.account_id = (SELECT auth.jwt()) -> ''app_metadata'' ->> ''provider_id''
            )
        )', schema_name, table_name, table_name, table_name);
END;
$$ LANGUAGE plpgsql;

-- Apply RLS policies to all relevant tables

DO $$
DECLARE
    tables text[][] := ARRAY[
        ARRAY['public', 'profile'],
        ARRAY['public', 'archive_upload'],
        ARRAY['public', 'account'],
        ARRAY['public', 'tweets'],
        ARRAY['public', 'likes'],
        ARRAY['public', 'followers'],
        ARRAY['public', 'following']
    ];
    t text[];
BEGIN
    FOREACH t SLICE 1 IN ARRAY tables
    LOOP
        PERFORM public.apply_public_rls_policies(t[1], t[2]);
    END LOOP;
END $$;

-- Apply entity policies
SELECT public.apply_public_entities_rls_policies('public', 'tweet_media');
SELECT public.apply_public_entities_rls_policies('public', 'tweet_urls');
SELECT public.apply_public_entities_rls_policies('public', 'user_mentions');