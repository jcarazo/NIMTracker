import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!url || !anonKey) {
  throw new Error('Missing VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY -- see frontend/.env.example')
}

// The anon/publishable key is safe to ship in the client bundle by
// design -- RLS is the actual security boundary, not key secrecy. See
// db/rls_policies.sql and CLAUDE.md, "Security model."
export const supabase = createClient(url, anonKey)
