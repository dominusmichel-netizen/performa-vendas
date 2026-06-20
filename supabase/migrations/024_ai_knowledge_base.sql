-- ============================================================
-- 024_ai_knowledge_base.sql — AI + Knowledge Base + Compliance
-- ============================================================

-- AI Config para cada account
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS ai_config JSONB DEFAULT '{}'::jsonb;

-- Knowledge Base com embeddings
CREATE TABLE IF NOT EXISTS knowledge_base (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  embedding vector(1536),
  source TEXT DEFAULT 'manual',
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_kb_account ON knowledge_base(account_id);
CREATE INDEX IF NOT EXISTS idx_kb_embedding ON knowledge_base USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

ALTER TABLE knowledge_base ENABLE ROW LEVEL SECURITY;

-- LGPD Consent Log
CREATE TABLE IF NOT EXISTS consent_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  consent_type TEXT NOT NULL CHECK (consent_type IN ('marketing', 'data_processing', 'third_party')),
  granted BOOLEAN NOT NULL DEFAULT true,
  ip TEXT,
  user_agent TEXT,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_consent_contact ON consent_log(contact_id);
CREATE INDEX IF NOT EXISTS idx_consent_account ON consent_log(account_id);

ALTER TABLE consent_log ENABLE ROW LEVEL SECURITY;

-- RLS Policies
DROP POLICY IF EXISTS "Users can manage own KB" ON knowledge_base;
CREATE POLICY "Users can manage own KB" ON knowledge_base FOR ALL
  USING (is_account_member(account_id))
  WITH CHECK (is_account_member(account_id));

DROP POLICY IF EXISTS "Users can view own consent logs" ON consent_log;
CREATE POLICY "Users can view own consent logs" ON consent_log FOR SELECT
  USING (is_account_member(account_id));

DROP POLICY IF EXISTS "Service role can insert consent" ON consent_log;
CREATE POLICY "Service role can insert consent" ON consent_log FOR INSERT
  WITH CHECK (true);

-- Enable Realtime for KB
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'knowledge_base'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE knowledge_base;
  END IF;
END $$;

-- Enable pgvector extension if not already enabled
CREATE EXTENSION IF NOT EXISTS vector;
